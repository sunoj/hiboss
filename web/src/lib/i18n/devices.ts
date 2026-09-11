// Four-locale copy for the Devices inventory and revocation flow.
// Exports typed dictionaries consumed by the existing locale dictionaries.
import type { LocaleDictionary, MessageParams } from './types';

export const enDevices = {
	'nav.devices': 'Devices', 'nav.short.devices': 'Devices',
	'page.devices': 'Devices', 'page.devicesSub': 'Your signed-in clients and their credentials.',
	'devices.empty': 'No clients yet', 'devices.thisBrowser': 'This browser',
	'devices.push': 'Push device', 'devices.signing': 'Signing key', 'devices.attached': 'Attached',
	'devices.none': 'None', 'devices.kind': 'Kind', 'devices.revoke': 'Revoke',
	'devices.revoking': 'Revoking…', 'devices.revoked': 'Revoked',
	'devices.confirm': (p: MessageParams) => `Revoke “${p.name}”? Its tokens and signing keys will stop working and its push registrations will be deleted.`,
} as const;
type DeviceKey = keyof typeof enDevices;

export const zhDevices = {
	'nav.devices': '设备', 'nav.short.devices': '设备',
	'page.devices': '设备', 'page.devicesSub': '已登录的客户端及其凭据。',
	'devices.empty': '暂无客户端', 'devices.thisBrowser': '此浏览器',
	'devices.push': '推送设备', 'devices.signing': '签名密钥', 'devices.attached': '已关联',
	'devices.none': '无', 'devices.kind': '类型', 'devices.revoke': '撤销',
	'devices.revoking': '正在撤销…', 'devices.revoked': '已撤销',
	'devices.confirm': (p: MessageParams) => `撤销“${p.name}”？其令牌和签名密钥将失效，推送注册将被删除。`,
} satisfies LocaleDictionary<DeviceKey>;

export const jaDevices = {
	'nav.devices': 'デバイス', 'nav.short.devices': 'デバイス',
	'page.devices': 'デバイス', 'page.devicesSub': 'ログイン中のクライアントと認証情報。',
	'devices.empty': 'クライアントはまだありません', 'devices.thisBrowser': 'このブラウザー',
	'devices.push': 'プッシュデバイス', 'devices.signing': '署名鍵', 'devices.attached': '登録済み',
	'devices.none': 'なし', 'devices.kind': '種類', 'devices.revoke': '失効',
	'devices.revoking': '失効中…', 'devices.revoked': '失効済み',
	'devices.confirm': (p: MessageParams) => `「${p.name}」を失効しますか？トークンと署名鍵が無効になり、プッシュ登録が削除されます。`,
} satisfies LocaleDictionary<DeviceKey>;

export const koDevices = {
	'nav.devices': '기기', 'nav.short.devices': '기기',
	'page.devices': '기기', 'page.devicesSub': '로그인한 클라이언트와 인증 정보입니다.',
	'devices.empty': '아직 클라이언트가 없습니다', 'devices.thisBrowser': '이 브라우저',
	'devices.push': '푸시 기기', 'devices.signing': '서명 키', 'devices.attached': '연결됨',
	'devices.none': '없음', 'devices.kind': '유형', 'devices.revoke': '해지',
	'devices.revoking': '해지 중…', 'devices.revoked': '해지됨',
	'devices.confirm': (p: MessageParams) => `“${p.name}”을(를) 해지할까요? 토큰과 서명 키가 무효화되고 푸시 등록이 삭제됩니다.`,
} satisfies LocaleDictionary<DeviceKey>;
