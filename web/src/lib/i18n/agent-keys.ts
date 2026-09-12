// Four-locale credential inventory, recovery and one-time bearer copy.
// Exports dictionaries consumed by locale entry points; depends on LocaleDictionary.
import type { LocaleDictionary } from './types';
export const enAgentKeys = {
  'keys.title': 'Agent keys', 'keys.empty': 'No keys', 'keys.label': 'Key label',
  'keys.mint': 'Create key', 'keys.revoke': 'Revoke', 'keys.revoked': 'Revoked',
  'keys.lastUsed': 'Last used', 'keys.once': 'Copy this key now. It will only be shown once.',
  'keys.confirm': 'Revoke this key? Every box using it will lose access.',
  'keys.copyFailed': 'Copy failed. Select and copy the key manually.'
} as const;
type Key = keyof typeof enAgentKeys;
export const zhAgentKeys = {
  'keys.title': '代理密钥', 'keys.empty': '暂无密钥', 'keys.label': '密钥标签',
  'keys.mint': '创建密钥', 'keys.revoke': '撤销', 'keys.revoked': '已撤销',
  'keys.lastUsed': '最近使用', 'keys.once': '请立即复制密钥，仅显示一次。',
  'keys.confirm': '撤销此密钥？所有使用它的设备都将失去访问权限。',
  'keys.copyFailed': '复制失败，请手动选择并复制密钥。'
} satisfies LocaleDictionary<Key>;
export const jaAgentKeys = {
  'keys.title': 'エージェントキー', 'keys.empty': 'キーはありません', 'keys.label': 'キーのラベル',
  'keys.mint': 'キーを作成', 'keys.revoke': '失効', 'keys.revoked': '失効済み',
  'keys.lastUsed': '最終使用', 'keys.once': '今すぐキーをコピーしてください。表示は一度だけです。',
  'keys.confirm': 'このキーを失効しますか？使用中のすべての端末がアクセスできなくなります。',
  'keys.copyFailed': 'コピーできませんでした。キーを選択して手動でコピーしてください。'
} satisfies LocaleDictionary<Key>;
export const koAgentKeys = {
  'keys.title': '에이전트 키', 'keys.empty': '키가 없습니다', 'keys.label': '키 이름',
  'keys.mint': '키 생성', 'keys.revoke': '폐기', 'keys.revoked': '폐기됨',
  'keys.lastUsed': '최근 사용', 'keys.once': '지금 키를 복사하세요. 한 번만 표시됩니다.',
  'keys.confirm': '이 키를 폐기할까요? 이 키를 사용하는 모든 기기의 접근이 차단됩니다.',
  'keys.copyFailed': '복사하지 못했습니다. 키를 선택하여 직접 복사하세요.'
} satisfies LocaleDictionary<Key>;
