// Four-locale notification settings copy, including mode and permission feedback.
// Exports typed dictionaries consumed by the existing locale system.
import type { LocaleDictionary, MessageParams } from './types';
export const enNotifications = {
  'nav.notifications': 'Notifications', 'nav.short.notifications': 'Notify',
  'notifications.title': 'Notifications', 'notifications.subtitle': 'Choose where and when you want to hear from your agents.',
  'notifications.empty': 'No destinations yet',
  'notifications.enabled': 'Enabled', 'notifications.priority': 'Minimum priority', 'notifications.quiet': 'Honour quiet hours',
  'notifications.routes': (p: MessageParams) => `${p.count} routes`, 'notifications.test': 'Test',
  'notifications.testSent': 'Test notification sent', 'notifications.testHint': 'Tests are available when destination delivery is on.',
  'notifications.nativeHint': 'Live streams show stored messages and do not support test pushes.',
  'notifications.preview': 'Destination delivery is not active yet. These settings take effect when it is enabled.',
  'notifications.readOnly': 'Your viewer role has read-only access.',
  'notifications.apns': 'Push device', 'notifications.native_live': 'Live client',
  'notifications.low': 'Low', 'notifications.normal': 'Normal', 'notifications.high': 'High', 'notifications.critical': 'Critical',
} as const;
type Key = keyof typeof enNotifications;
export const zhNotifications = {
  'nav.notifications': '通知', 'nav.short.notifications': '通知',
  'notifications.title': '通知', 'notifications.subtitle': '选择接收智能体通知的位置和时间。',
  'notifications.empty': '暂无通知目标',
  'notifications.enabled': '启用', 'notifications.priority': '最低优先级', 'notifications.quiet': '遵守免打扰时间',
  'notifications.routes': (p: MessageParams) => `${p.count} 条路由`, 'notifications.test': '测试', 'notifications.testSent': '测试通知已发送',
  'notifications.testHint': '通知目标投递启用后才可测试。', 'notifications.nativeHint': '实时客户端显示已存储的消息，不支持测试推送。',
  'notifications.preview': '通知目标投递尚未启用。这些设置将在启用后生效。', 'notifications.readOnly': '查看者角色仅有读取权限。',
  'notifications.apns': '推送设备', 'notifications.native_live': '实时客户端',
  'notifications.low': '低', 'notifications.normal': '普通', 'notifications.high': '高', 'notifications.critical': '紧急',
} satisfies LocaleDictionary<Key>;
export const jaNotifications = {
  'nav.notifications': '通知', 'nav.short.notifications': '通知',
  'notifications.title': '通知', 'notifications.subtitle': 'エージェントからの通知の受信先と時間を選択します。',
  'notifications.empty': '通知先はまだありません',
  'notifications.enabled': '有効', 'notifications.priority': '最低優先度', 'notifications.quiet': '通知休止時間を適用',
  'notifications.routes': (p: MessageParams) => `${p.count} 件のルート`, 'notifications.test': 'テスト', 'notifications.testSent': 'テスト通知を送信しました',
  'notifications.testHint': '通知先への配信が有効になるとテストできます。', 'notifications.nativeHint': 'ライブクライアントは保存済みメッセージを表示するため、テストプッシュには対応していません。',
  'notifications.preview': '通知先への配信はまだ無効です。有効になると設定が適用されます。', 'notifications.readOnly': '閲覧者は読み取り専用です。',
  'notifications.apns': 'プッシュデバイス', 'notifications.native_live': 'ライブクライアント',
  'notifications.low': '低', 'notifications.normal': '通常', 'notifications.high': '高', 'notifications.critical': '緊急',
} satisfies LocaleDictionary<Key>;
export const koNotifications = {
  'nav.notifications': '알림', 'nav.short.notifications': '알림',
  'notifications.title': '알림', 'notifications.subtitle': '에이전트 알림을 받을 위치와 시간을 선택하세요.',
  'notifications.empty': '아직 알림 대상이 없습니다',
  'notifications.enabled': '활성화', 'notifications.priority': '최소 우선순위', 'notifications.quiet': '방해 금지 시간 적용',
  'notifications.routes': (p: MessageParams) => `경로 ${p.count}개`, 'notifications.test': '테스트', 'notifications.testSent': '테스트 알림을 보냈습니다',
  'notifications.testHint': '알림 대상 전송이 활성화되면 테스트할 수 있습니다.', 'notifications.nativeHint': '실시간 클라이언트는 저장된 메시지를 표시하며 테스트 푸시를 지원하지 않습니다.',
  'notifications.preview': '알림 대상 전송이 아직 활성화되지 않았습니다. 활성화되면 설정이 적용됩니다.', 'notifications.readOnly': '뷰어 역할은 읽기 전용입니다.',
  'notifications.apns': '푸시 기기', 'notifications.native_live': '실시간 클라이언트',
  'notifications.low': '낮음', 'notifications.normal': '보통', 'notifications.high': '높음', 'notifications.critical': '긴급',
} satisfies LocaleDictionary<Key>;
