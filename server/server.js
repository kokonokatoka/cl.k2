const { WebSocketServer } = require('ws');

const PORT = process.env.PORT || 8080;
const wss = new WebSocketServer({ port: PORT });

// 接続中プレイヤーの管理
const players = new Map();

console.log(`[Relay Server] Listening on port ${PORT}...`);

wss.on('connection', (ws) => {
    let playerId = null;

    ws.on('message', (message) => {
        try {
            const data = JSON.parse(message.toString());
            const type = data.type;

            if (type === 'join') {
                playerId = data.id;
                players.set(playerId, {
                    id: data.id,
                    name: data.name || 'Player',
                    color: data.color || '#3498db',
                    x: data.x || 576,
                    y: data.y || 324,
                    ws: ws
                });

                console.log(`[Join] ${data.name} (${playerId}) connected. Total players: ${players.size}`);

                // 新規プレイヤーに既存プレイヤー一覧を送信
                const existingPlayers = [];
                for (const [id, p] of players.entries()) {
                    if (id !== playerId) {
                        existingPlayers.push({
                            id: p.id,
                            name: p.name,
                            color: p.color,
                            x: p.x,
                            y: p.y
                        });
                    }
                }

                ws.send(JSON.stringify({
                    type: 'welcome',
                    assigned_id: playerId,
                    players: existingPlayers
                }));

                // 他の全員に新規参加をブロードキャスト
                broadcast(data, playerId);

            } else if (type === 'move') {
                if (players.has(playerId)) {
                    const p = players.get(playerId);
                    p.x = data.x;
                    p.y = data.y;
                }
                broadcast(data, playerId);

            } else if (type === 'action' || type === 'chat') {
                broadcast(data, playerId);

            } else if (type === 'leave') {
                handleDisconnect(playerId);
            }
        } catch (e) {
            console.error('[Error] Invalid message format:', e.message);
        }
    });

    ws.on('close', () => {
        if (playerId) {
            handleDisconnect(playerId);
        }
    });

    ws.on('error', (err) => {
        console.error(`[Socket Error] for ${playerId}:`, err.message);
    });
});

function broadcast(data, excludeId) {
    const jsonStr = JSON.stringify(data);
    for (const [id, p] of players.entries()) {
        if (id !== excludeId && p.ws.readyState === 1 /* OPEN */) {
            p.ws.send(jsonStr);
        }
    }
}

function handleDisconnect(id) {
    if (players.has(id)) {
        const p = players.get(id);
        console.log(`[Leave] ${p.name} (${id}) left. Total players: ${players.size - 1}`);
        players.delete(id);
        broadcast({ type: 'leave', id: id }, id);
    }
}
