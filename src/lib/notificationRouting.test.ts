import { describe, expect, it } from 'vitest';
import { resolveNotificationLink } from './notificationRouting';

describe('resolveNotificationLink', () => {
  it('keeps an explicit merchant chat context for a merchant+buyer account', () => {
    expect(resolveNotificationLink({ type: 'chat', link: '/merchant/chat?conversationId=c1' }, ['merchant', 'buyer']))
      .toBe('/merchant/chat?conversationId=c1');
  });

  it('repairs legacy buyer links for merchant+buyer accounts', () => {
    expect(resolveNotificationLink({ type: 'chat', link: '/buyer/chat?conversationId=c0' }, ['merchant', 'buyer']))
      .toBe('/merchant/chat?conversationId=c0');
  });

  it('keeps an explicit courier chat context for a courier+buyer account', () => {
    expect(resolveNotificationLink({ type: 'chat', link: '/courier/chat?orderId=o1' }, ['courier', 'buyer']))
      .toBe('/courier/chat?orderId=o1');
  });

  it('repairs legacy buyer links for courier+buyer accounts', () => {
    expect(resolveNotificationLink({ type: 'chat', link: '/buyer/chat?conversationId=courier-1' }, ['courier', 'buyer']))
      .toBe('/courier/chat?conversationId=courier-1');
  });

  it('repairs legacy buyer links for admin-desa+buyer accounts', () => {
    expect(resolveNotificationLink({ type: 'chat', link: '/buyer/chat?conversationId=desa-1' }, ['admin_desa', 'buyer']))
      .toBe('/desa/chat?conversationId=desa-1');
  });

  it('routes a generic chat link to the role dashboard when no scoped link exists', () => {
    expect(resolveNotificationLink({ type: 'chat', link: '/chat', data: { conversation_id: 'c2' } }, ['merchant', 'buyer']))
      .toBe('/merchant/chat?conversationId=c2');
  });

  it('uses the explicit admin/desa link instead of multi-role heuristics', () => {
    expect(resolveNotificationLink({ type: 'chat', link: '/desa?conversationId=c3' }, ['admin', 'admin_desa', 'buyer']))
      .toBe('/desa?conversationId=c3');
  });

  it('preserves conversation identifiers from JSON notification data', () => {
    expect(resolveNotificationLink({ type: 'chat', link: '/buyer/chat', data: JSON.stringify({ conversation_id: 'c4', order_id: 'o4' }) }, ['buyer']))
      .toBe('/buyer/chat?conversationId=c4&orderId=o4');
  });

  it('keeps role-specific order routing for legacy order links', () => {
    expect(resolveNotificationLink({ type: 'order', link: '/orders', data: { order_id: 'o5' } }, ['merchant', 'buyer']))
      .toBe('/merchant/orders?orderId=o5');
  });

  it('opens the merchant chat when conversation_id is stored on the notification row', () => {
    expect(resolveNotificationLink({ type: 'info', conversation_id: 'admin-merchant-1' }, ['merchant']))
      .toBe('/merchant/chat?conversationId=admin-merchant-1');
  });

  it('opens the courier chat when conversation_id is stored on the notification row', () => {
    expect(resolveNotificationLink({ type: 'info', conversation_id: 'admin-courier-1' }, ['courier']))
      .toBe('/courier/chat?conversationId=admin-courier-1');
  });

  it('repairs legacy buyer links for admin accounts', () => {
    expect(resolveNotificationLink({ type: 'chat', link: '/buyer/chat?conversationId=admin-1' }, ['admin']))
      .toBe('/admin/chat?conversationId=admin-1');
  });
});
