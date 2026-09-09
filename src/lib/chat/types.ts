export type ChatContextType = 'order' | 'ride' | 'direct';

export type ConversationType =
  | 'buyer_merchant'
  | 'buyer_courier'
  | 'merchant_courier'
  | 'passenger_courier';

export interface ChatConversation {
  id: string;
  context_type: ChatContextType;
  order_id: string | null;
  ride_request_id: string | null;
  merchant_id: string | null;
  buyer_user_id: string | null;
  conversation_type: ConversationType;
  status: 'active' | 'closed' | 'archived';
  last_message_id: string | null;
  last_message_at: string | null;
  retention_until: string | null;
}

export interface ConversationMessage {
  id: string;
  conversation_id: string | null;
  sender_id: string;
  receiver_id: string | null;
  message: string;
  body: string | null;
  is_read: boolean;
  created_at: string;
  auto_delete_at: string | null;
  soft_delete_at: string | null;
  hard_delete_at: string | null;
  chat_type: string | null;
  image_url: string | null;
  client_message_id: string | null;
  deleted_at: string | null;
  deleted_reason: string | null;
}
