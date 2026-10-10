export function buildAdminPushTestPayload(userId: string, title: string, body: string) {
  return {
    user_id: userId,
    title,
    body,
    url: '/',
  };
}
