import { Channel, NewMessage } from './types.js';
import { formatLocalTime } from './timezone.js';

export function escapeXml(s: string): string {
  if (!s) return '';
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

/**
 * Marker embedded in message content by the Telegram channel when a file
 * is downloaded. Format: [attachment-path:/workspace/attachments/...]
 * This survives the database without a schema change and is stripped out
 * here to be rendered as a proper XML child element.
 */
const ATTACHMENT_PATH_RE = /\[attachment-path:([^\]]+)\]/g;

export function formatMessages(
  messages: NewMessage[],
  timezone: string,
): string {
  const lines = messages.map((m) => {
    const displayTime = formatLocalTime(m.timestamp, timezone);

    // Extract attachment paths embedded in the content, leaving clean text
    const attachmentPaths: string[] = [];
    const cleanContent = m.content
      .replace(ATTACHMENT_PATH_RE, (_, p) => {
        attachmentPaths.push(p);
        return '';
      })
      .trim();

    let inner = escapeXml(cleanContent);
    if (attachmentPaths.length > 0) {
      inner +=
        '\n' +
        attachmentPaths
          .map((p) => `<attachment path="${escapeXml(p)}" />`)
          .join('\n');
    }

    return `<message sender="${escapeXml(m.sender_name)}" time="${escapeXml(displayTime)}">${inner}</message>`;
  });

  const header = `<context timezone="${escapeXml(timezone)}" />\n`;

  return `${header}<messages>\n${lines.join('\n')}\n</messages>`;
}

export function stripInternalTags(text: string): string {
  return text.replace(/<internal>[\s\S]*?<\/internal>/g, '').trim();
}

export function formatOutbound(rawText: string): string {
  const text = stripInternalTags(rawText);
  if (!text) return '';
  return text;
}

export function routeOutbound(
  channels: Channel[],
  jid: string,
  text: string,
): Promise<void> {
  const channel = channels.find((c) => c.ownsJid(jid) && c.isConnected());
  if (!channel) throw new Error(`No channel for JID: ${jid}`);
  return channel.sendMessage(jid, text);
}

export function findChannel(
  channels: Channel[],
  jid: string,
): Channel | undefined {
  return channels.find((c) => c.ownsJid(jid));
}
