// Four-locale copy for project inventory, display names and explicit merges.
// Exports dictionaries consumed by the existing locale entry points.
import type { LocaleDictionary, MessageParams } from './types';
export const enProjects = {
  'nav.projects': 'Projects', 'nav.short.projects': 'Projects',
  'projects.description': 'Codebases, their aliases and activity.', 'projects.empty': 'No projects yet',
  'projects.aliases': 'Aliases', 'projects.lastPost': 'Last post', 'projects.displayName': 'Display name',
  'projects.mergeInto': 'Merge into', 'projects.choose': 'Choose a project', 'projects.merge': 'Merge', 'projects.save': 'Save name',
  'projects.confirm': (p: MessageParams) => `Merge “${p.source}” into “${p.target}”? Sessions, posts, aliases and routes move to the target. The target profile is kept. This cannot be undone.`,
} as const;
type Key = keyof typeof enProjects;
export const zhProjects = {
  'nav.projects': '项目', 'nav.short.projects': '项目',
  'projects.description': '代码库、别名与活动。', 'projects.empty': '暂无项目',
  'projects.aliases': '别名', 'projects.lastPost': '最近动态', 'projects.displayName': '显示名称',
  'projects.mergeInto': '合并到', 'projects.choose': '选择项目', 'projects.merge': '合并', 'projects.save': '保存名称',
  'projects.confirm': (p: MessageParams) => `将“${p.source}”合并到“${p.target}”？会话、动态、别名及路由将移至目标，并保留目标资料。此操作无法撤销。`,
} satisfies LocaleDictionary<Key>;
export const jaProjects = {
  'nav.projects': 'プロジェクト', 'nav.short.projects': 'プロジェクト',
  'projects.description': 'コードベース、別名とアクティビティ。', 'projects.empty': 'プロジェクトはまだありません',
  'projects.aliases': '別名', 'projects.lastPost': '最新の投稿', 'projects.displayName': '表示名',
  'projects.mergeInto': '統合先', 'projects.choose': 'プロジェクトを選択', 'projects.merge': '統合', 'projects.save': '名前を保存',
  'projects.confirm': (p: MessageParams) => `「${p.source}」を「${p.target}」に統合しますか？セッション、投稿、別名、ルートが移動し、統合先のプロフィールが保持されます。元に戻せません。`,
} satisfies LocaleDictionary<Key>;
export const koProjects = {
  'nav.projects': '프로젝트', 'nav.short.projects': '프로젝트',
  'projects.description': '코드베이스, 별칭 및 활동입니다.', 'projects.empty': '아직 프로젝트가 없습니다',
  'projects.aliases': '별칭', 'projects.lastPost': '최근 게시물', 'projects.displayName': '표시 이름',
  'projects.mergeInto': '병합 대상', 'projects.choose': '프로젝트 선택', 'projects.merge': '병합', 'projects.save': '이름 저장',
  'projects.confirm': (p: MessageParams) => `“${p.source}”을(를) “${p.target}”에 병합할까요? 세션, 게시물, 별칭과 경로가 이동하고 대상 프로필이 유지됩니다. 되돌릴 수 없습니다.`,
} satisfies LocaleDictionary<Key>;
