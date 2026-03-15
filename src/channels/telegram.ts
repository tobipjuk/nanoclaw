import fs from 'fs';
import https from 'https';
import os from 'os';
import path from 'path';
import { Api, Bot } from 'grammy';

import { ASSISTANT_NAME, TRIGGER_PATTERN } from '../config.js';
import { readEnvFile } from '../env.js';
import { logger } from '../logger.js';
import { registerChannel, ChannelOpts } from './registry.js';
import {
  Channel,
  OnChatMetadata,
  OnInboundMessage,
  RegisteredGroup,
} from '../types.js';

export interface TelegramChannelOpts {
  onMessage: OnInboundMessage;
  onChatMetadata: OnChatMetadata;
  registeredGroups: () => Record<string, RegisteredGroup>;
}

/**
 * Send a message with Telegram Markdown parse mode, falling back to plain text.
 * Claude's output naturally matches Telegram's Markdown v1 format:
 *   *bold*, _italic_, `code`, ```code blocks```, [links](url)
 */
async function sendTelegramMessage(
  api: { sendMessage: Api['sendMessage'] },
  chatId: string | number,
  text: string,
  options: { message_thread_id?: number } = {},
): Promise<void> {
  try {
    await api.sendMessage(chatId, text, {
      ...options,
      parse_mode: 'Markdown',
    });
  } catch (err) {
    // Fallback: send as plain text if Markdown parsing fails
    logger.debug({ err }, 'Markdown send failed, falling back to plain text');
    await api.sendMessage(chatId, text, options);
  }
}

/** Root directory on the host where Telegram attachments are downloaded */
const ATTACHMENTS_HOST_DIR = path.join(os.homedir(), 'nanoclaw-attachments');

/** Corresponding path inside the agent container */
const ATTACHMENTS_CONTAINER_DIR = '/workspace/attachments';

/**
 * Marker embedded in message content to carry the container-visible attachment path
 * through the database without a schema change.
 * Format: [attachment-path:/workspace/attachments/...]
 */
const ATTACHMENT_PATH_MARKER = '[attachment-path:';

export {
  ATTACHMENTS_HOST_DIR,
  ATTACHMENTS_CONTAINER_DIR,
  ATTACHMENT_PATH_MARKER,
};

/**
 * Transcribe an audio file using the OpenAI Whisper API.
 * Returns the transcribed text, or null if transcription fails or the API key is not set.
 */
async function transcribeAudio(filePath: string): Promise<string | null> {
  const apiKey =
    process.env.OPENAI_API_KEY || readEnvFile(['OPENAI_API_KEY']).OPENAI_API_KEY;
  if (!apiKey) {
    logger.warn('OPENAI_API_KEY not set — voice transcription skipped');
    return null;
  }

  try {
    const fileBuffer = fs.readFileSync(filePath);
    const blob = new Blob([fileBuffer], { type: 'audio/ogg' });
    const form = new FormData();
    form.append('file', blob, 'voice.ogg');
    form.append('model', 'whisper-1');

    const response = await fetch('https://api.openai.com/v1/audio/transcriptions', {
      method: 'POST',
      headers: { Authorization: `Bearer ${apiKey}` },
      body: form,
    });

    if (!response.ok) {
      logger.warn({ status: response.status }, 'Whisper API error');
      return null;
    }

    const data = (await response.json()) as { text?: string };
    return data.text?.trim() || null;
  } catch (err) {
    logger.warn({ err, filePath }, 'Voice transcription failed');
    return null;
  }
}

export class TelegramChannel implements Channel {
  name = 'telegram';

  private bot: Bot | null = null;
  private opts: TelegramChannelOpts;
  private botToken: string;
  private typingIntervals: Map<string, ReturnType<typeof setInterval>> =
    new Map();

  constructor(botToken: string, opts: TelegramChannelOpts) {
    this.botToken = botToken;
    this.opts = opts;
    // Ensure the attachments directory exists on startup
    fs.mkdirSync(ATTACHMENTS_HOST_DIR, { recursive: true });
  }

  /**
   * Download a Telegram file by file_id and save it to the host attachments directory.
   * Returns the container-visible path, or null if the download fails.
   */
  private async downloadAttachment(
    fileId: string,
    chatJid: string,
    msgId: string,
    filename: string,
  ): Promise<string | null> {
    if (!this.bot) return null;
    try {
      const file = await this.bot.api.getFile(fileId);
      if (!file.file_path) return null;

      // Make chatJid safe for use as a directory name (e.g. "tg:-123456" → "tg--123456")
      const safeChatJid = chatJid.replace(/[^a-zA-Z0-9-]/g, '-');
      const dir = path.join(ATTACHMENTS_HOST_DIR, safeChatJid, msgId);
      fs.mkdirSync(dir, { recursive: true });

      const localPath = path.join(dir, filename);
      const containerPath = `${ATTACHMENTS_CONTAINER_DIR}/${safeChatJid}/${msgId}/${filename}`;
      const url = `https://api.telegram.org/file/bot${this.botToken}/${file.file_path}`;

      await new Promise<void>((resolve, reject) => {
        const fileStream = fs.createWriteStream(localPath);
        https
          .get(url, (response) => {
            response.pipe(fileStream);
            fileStream.on('finish', () => {
              fileStream.close();
              resolve();
            });
            fileStream.on('error', reject);
            response.on('error', reject);
          })
          .on('error', reject);
      });

      logger.info(
        { chatJid, msgId, filename, localPath },
        'Telegram attachment downloaded',
      );
      return containerPath;
    } catch (err) {
      logger.warn(
        { err, fileId, chatJid, msgId },
        'Failed to download Telegram attachment',
      );
      return null;
    }
  }

  async connect(): Promise<void> {
    this.bot = new Bot(this.botToken, {
      client: {
        baseFetchConfig: { agent: https.globalAgent, compress: true },
      },
    });

    // Command to get chat ID (useful for registration)
    this.bot.command('chatid', (ctx) => {
      const chatId = ctx.chat.id;
      const chatType = ctx.chat.type;
      const chatName =
        chatType === 'private'
          ? ctx.from?.first_name || 'Private'
          : (ctx.chat as any).title || 'Unknown';

      ctx.reply(
        `Chat ID: \`tg:${chatId}\`\nName: ${chatName}\nType: ${chatType}`,
        { parse_mode: 'Markdown' },
      );
    });

    // Command to check bot status
    this.bot.command('ping', (ctx) => {
      ctx.reply(`${ASSISTANT_NAME} is online.`);
    });

    // Telegram bot commands handled above — skip them in the general handler
    // so they don't also get stored as messages. All other /commands flow through.
    const TELEGRAM_BOT_COMMANDS = new Set(['chatid', 'ping']);

    this.bot.on('message:text', async (ctx) => {
      if (ctx.message.text.startsWith('/')) {
        const cmd = ctx.message.text.slice(1).split(/[\s@]/)[0].toLowerCase();
        if (TELEGRAM_BOT_COMMANDS.has(cmd)) return;
      }

      const chatJid = `tg:${ctx.chat.id}`;
      let content = ctx.message.text;
      const timestamp = new Date(ctx.message.date * 1000).toISOString();
      const senderName =
        ctx.from?.first_name ||
        ctx.from?.username ||
        ctx.from?.id.toString() ||
        'Unknown';
      const sender = ctx.from?.id.toString() || '';
      const msgId = ctx.message.message_id.toString();

      // Determine chat name
      const chatName =
        ctx.chat.type === 'private'
          ? senderName
          : (ctx.chat as any).title || chatJid;

      // Translate Telegram @bot_username mentions into TRIGGER_PATTERN format.
      // Telegram @mentions (e.g., @andy_ai_bot) won't match TRIGGER_PATTERN
      // (e.g., ^@Andy\b), so we prepend the trigger when the bot is @mentioned.
      const botUsername = ctx.me?.username?.toLowerCase();
      if (botUsername) {
        const entities = ctx.message.entities || [];
        const isBotMentioned = entities.some((entity) => {
          if (entity.type === 'mention') {
            const mentionText = content
              .substring(entity.offset, entity.offset + entity.length)
              .toLowerCase();
            return mentionText === `@${botUsername}`;
          }
          return false;
        });
        if (isBotMentioned && !TRIGGER_PATTERN.test(content)) {
          content = `@${ASSISTANT_NAME} ${content}`;
        }
      }

      // Store chat metadata for discovery
      const isGroup =
        ctx.chat.type === 'group' || ctx.chat.type === 'supergroup';
      this.opts.onChatMetadata(
        chatJid,
        timestamp,
        chatName,
        'telegram',
        isGroup,
      );

      // Only deliver full message for registered groups
      const group = this.opts.registeredGroups()[chatJid];
      if (!group) {
        logger.debug(
          { chatJid, chatName },
          'Message from unregistered Telegram chat',
        );
        return;
      }

      // Deliver message — startMessageLoop() will pick it up
      this.opts.onMessage(chatJid, {
        id: msgId,
        chat_jid: chatJid,
        sender,
        sender_name: senderName,
        content,
        timestamp,
        is_from_me: false,
      });

      logger.info(
        { chatJid, chatName, sender: senderName },
        'Telegram message stored',
      );
    });

    // Handle non-text messages — download supported types (photos, documents)
    // and embed the container path in the content so the agent can access the file.
    const storeNonText = (
      ctx: any,
      placeholder: string,
      containerPath?: string,
    ) => {
      const chatJid = `tg:${ctx.chat.id}`;
      const group = this.opts.registeredGroups()[chatJid];
      if (!group) return;

      const timestamp = new Date(ctx.message.date * 1000).toISOString();
      const senderName =
        ctx.from?.first_name ||
        ctx.from?.username ||
        ctx.from?.id?.toString() ||
        'Unknown';
      const caption = ctx.message.caption ? ` ${ctx.message.caption}` : '';

      // Embed the container path as a marker in the content so it survives the DB
      // without a schema change. formatMessages() will strip and render it as XML.
      const attachmentMarker = containerPath
        ? `\n${ATTACHMENT_PATH_MARKER}${containerPath}]`
        : '';

      const isGroup =
        ctx.chat.type === 'group' || ctx.chat.type === 'supergroup';
      this.opts.onChatMetadata(
        chatJid,
        timestamp,
        undefined,
        'telegram',
        isGroup,
      );
      this.opts.onMessage(chatJid, {
        id: ctx.message.message_id.toString(),
        chat_jid: chatJid,
        sender: ctx.from?.id?.toString() || '',
        sender_name: senderName,
        content: `${placeholder}${caption}${attachmentMarker}`,
        timestamp,
        is_from_me: false,
      });
    };

    this.bot.on('message:photo', async (ctx) => {
      const photo = ctx.message.photo?.at(-1);
      const msgId = ctx.message.message_id.toString();
      const chatJid = `tg:${ctx.chat.id}`;
      let containerPath: string | undefined;
      if (photo) {
        containerPath =
          (await this.downloadAttachment(
            photo.file_id,
            chatJid,
            msgId,
            'photo.jpg',
          )) ?? undefined;
      }
      storeNonText(ctx, '[Photo]', containerPath);
    });

    this.bot.on('message:document', async (ctx) => {
      const doc = ctx.message.document;
      const name = doc?.file_name || 'file';
      const msgId = ctx.message.message_id.toString();
      const chatJid = `tg:${ctx.chat.id}`;
      let containerPath: string | undefined;
      if (doc) {
        containerPath =
          (await this.downloadAttachment(doc.file_id, chatJid, msgId, name)) ??
          undefined;
      }
      storeNonText(ctx, `[Document: ${name}]`, containerPath);
    });

    this.bot.on('message:video', (ctx) => storeNonText(ctx, '[Video]'));
    this.bot.on('message:voice', async (ctx) => {
      const voice = ctx.message.voice;
      const msgId = ctx.message.message_id.toString();
      const chatJid = `tg:${ctx.chat.id}`;
      if (voice) {
        const containerPath = await this.downloadAttachment(
          voice.file_id,
          chatJid,
          msgId,
          'voice.ogg',
        );
        if (containerPath) {
          // Derive the host path from the container path for transcription
          const hostPath = containerPath.replace(
            ATTACHMENTS_CONTAINER_DIR,
            ATTACHMENTS_HOST_DIR,
          );
          const transcription = await transcribeAudio(hostPath);
          if (transcription) {
            storeNonText(ctx, `[Voice: ${transcription}]`);
            return;
          }
        }
      }
      storeNonText(ctx, '[Voice message]');
    });
    this.bot.on('message:audio', (ctx) => storeNonText(ctx, '[Audio]'));
    this.bot.on('message:sticker', (ctx) => {
      const emoji = ctx.message.sticker?.emoji || '';
      storeNonText(ctx, `[Sticker ${emoji}]`);
    });
    this.bot.on('message:location', (ctx) => storeNonText(ctx, '[Location]'));
    this.bot.on('message:contact', (ctx) => storeNonText(ctx, '[Contact]'));

    // Handle message reactions — delivered as structured content so Orion can act on them
    this.bot.on('message_reaction', (ctx) => {
      const chatJid = `tg:${ctx.chat.id}`;
      const group = this.opts.registeredGroups()[chatJid];
      if (!group) return;

      const reactions = ctx.messageReaction.new_reaction
        .map((r) => (r.type === 'emoji' ? r.emoji : r.type))
        .join(' ');

      // Ignore reaction-removal events (new_reaction is empty)
      if (!reactions) return;

      const senderName =
        ctx.from?.first_name || ctx.from?.username || 'Unknown';
      const timestamp = new Date(ctx.messageReaction.date * 1000).toISOString();
      const reactedToId = ctx.messageReaction.message_id;

      this.opts.onMessage(chatJid, {
        id: `reaction-${reactedToId}-${Date.now()}`,
        chat_jid: chatJid,
        sender: ctx.from?.id?.toString() || '',
        sender_name: senderName,
        content: `[Reaction: ${reactions} on message ${reactedToId}]`,
        timestamp,
        is_from_me: false,
      });

      logger.info(
        { chatJid, reactions, reactedToId, sender: senderName },
        'Telegram reaction received',
      );
    });

    // Handle errors gracefully
    this.bot.catch((err) => {
      logger.error({ err: err.message }, 'Telegram bot error');
    });

    // Start polling — returns a Promise that resolves when started
    return new Promise<void>((resolve) => {
      this.bot!.start({
        allowed_updates: ['message', 'message_reaction'],
        onStart: (botInfo) => {
          logger.info(
            { username: botInfo.username, id: botInfo.id },
            'Telegram bot connected',
          );
          console.log(`\n  Telegram bot: @${botInfo.username}`);
          console.log(
            `  Send /chatid to the bot to get a chat's registration ID\n`,
          );
          resolve();
        },
      });
    });
  }

  async sendMessage(jid: string, text: string): Promise<void> {
    if (!this.bot) {
      logger.warn('Telegram bot not initialized');
      return;
    }

    try {
      const numericId = jid.replace(/^tg:/, '');

      // Telegram has a 4096 character limit per message — split if needed
      const MAX_LENGTH = 4096;
      if (text.length <= MAX_LENGTH) {
        await sendTelegramMessage(this.bot.api, numericId, text);
      } else {
        for (let i = 0; i < text.length; i += MAX_LENGTH) {
          await sendTelegramMessage(
            this.bot.api,
            numericId,
            text.slice(i, i + MAX_LENGTH),
          );
        }
      }
      logger.info({ jid, length: text.length }, 'Telegram message sent');
    } catch (err) {
      logger.error({ jid, err }, 'Failed to send Telegram message');
    }
  }

  isConnected(): boolean {
    return this.bot !== null;
  }

  ownsJid(jid: string): boolean {
    return jid.startsWith('tg:');
  }

  async disconnect(): Promise<void> {
    if (this.bot) {
      this.bot.stop();
      this.bot = null;
      logger.info('Telegram bot stopped');
    }
  }

  async setTyping(jid: string, isTyping: boolean): Promise<void> {
    if (!this.bot) return;

    if (!isTyping) {
      const existing = this.typingIntervals.get(jid);
      if (existing) {
        clearInterval(existing);
        this.typingIntervals.delete(jid);
      }
      return;
    }

    // Don't start a duplicate interval
    if (this.typingIntervals.has(jid)) return;

    const numericId = jid.replace(/^tg:/, '');
    const sendTyping = async () => {
      try {
        await this.bot!.api.sendChatAction(numericId, 'typing');
      } catch (err) {
        logger.debug({ jid, err }, 'Failed to send Telegram typing indicator');
      }
    };

    // Send immediately, then repeat every 4s (Telegram typing lasts ~5s)
    await sendTyping();
    const interval = setInterval(sendTyping, 4000);
    this.typingIntervals.set(jid, interval);
  }
}

registerChannel('telegram', (opts: ChannelOpts) => {
  const envVars = readEnvFile(['TELEGRAM_BOT_TOKEN']);
  const token =
    process.env.TELEGRAM_BOT_TOKEN || envVars.TELEGRAM_BOT_TOKEN || '';
  if (!token) {
    logger.warn('Telegram: TELEGRAM_BOT_TOKEN not set');
    return null;
  }
  return new TelegramChannel(token, opts);
});
