"""Reference SQL and access sets for the dashboard pagination regression.
Models main and the original 0048 implementation independently of current routes.
"""

previous_indexes = """
CREATE INDEX idx_messages_created ON messages(created_at DESC, agent_id);
CREATE INDEX idx_messages_boss_created ON messages(created_at DESC, agent_id, status)
  WHERE direction = 'agent_to_boss';
CREATE INDEX idx_sessions_seen ON sessions(last_seen_at DESC, agent_id);
"""


def message_cases(db):
    scopes = {'all': list(range(13)), 'low_two': [11, 12], 'low_one': [12], 'three': [1, 4, 8], 'empty': []}
    for scope, numbers in scopes.items():
        agents = [f'agent-{number:02}' for number in numbers] or ['no-agent']
        for direction in ['all', 'boss']:
            where = 'agent_id IN (' + ','.join('?' for _ in agents) + ')'
            if direction == 'boss':
                where += " AND direction = 'agent_to_boss'"
            total = db.execute('SELECT count(*) FROM messages WHERE ' + where, agents).fetchone()[0]
            for offset in sorted({0, 500, total, total + 1000}):
                yield f'{scope}_{direction}_offset_{offset}', agents, direction, offset


def reference_page(where, offset, version, direction, agent_count=13):
    select = ('SELECT messages.*, api_keys.name AS agent_name, sessions.label AS session_label, '
              'sessions.branch AS session_branch, sessions.status AS session_status')
    joins = ('LEFT JOIN api_keys ON api_keys.id = messages.agent_id '
             'LEFT JOIN sessions ON sessions.id = messages.session_id')
    order = 'messages.created_at DESC' + (', messages.id DESC' if version == 'canonical' else '')
    if version == 'previous':
        index = 'idx_messages_boss_created' if direction == 'boss' else 'idx_messages_created'
        hint = f'INDEXED BY {index}' if agent_count > 1 else ''
        inner = f'SELECT * FROM messages {hint} WHERE {where} ORDER BY created_at DESC LIMIT 50 OFFSET {offset}'
        return f'{select} FROM ({inner}) messages {joins} ORDER BY {order}'
    return f'{select} FROM (SELECT * FROM messages WHERE {where}) messages {joins} ORDER BY {order} LIMIT 50 OFFSET {offset}'
