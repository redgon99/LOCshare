// server.js
require('dotenv').config();
const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const { v4: uuidv4 } = require('uuid');
const path = require('path');
const helmet = require('helmet');
const compression = require('compression');
const cors = require('cors');

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
  cors: { origin: '*' },
});

app.use(helmet({ contentSecurityPolicy: false }));
app.use(compression());
app.use(cors());
app.use(express.json());

const PORT = process.env.PORT || 8080;
const BASE_URL = process.env.PUBLIC_BASE_URL || `http://localhost:${PORT}`;
const ROOM_TTL_MINUTES = parseInt(process.env.ROOM_TTL_MINUTES || '120', 10);

// 메모리 방 저장 (프로덕션: Redis 권장)
// rooms[token] = { createdAt: Date, expiresAt: Date }
const rooms = new Map();

function createRoom() {
  const token = uuidv4().replace(/-/g, '');
  const now = new Date();
  const expiresAt = new Date(now.getTime() + ROOM_TTL_MINUTES * 60000);
  rooms.set(token, { createdAt: now, expiresAt });
  return token;
}

function roomExistsAndActive(token) {
  const r = rooms.get(token);
  if (!r) return false;
  return r.expiresAt > new Date();
}

// 방 생성 API (문자 발송 전 링크 발급용)
app.post('/api/rooms', (req, res) => {
  const token = createRoom();
  const link = `${BASE_URL}/r/${token}`;
  res.json({ token, link, expiresInMinutes: ROOM_TTL_MINUTES });
});

// 정적 파일 제공
app.use('/public', express.static(path.join(__dirname, 'public')));

// SPA 라우팅: /r/:token → 클라이언트 앱
app.get('/r/:token', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// 기본 루트: 간단 헬스체크
app.get('/', (req, res) => {
  res.send('OK');
});

// 소켓 이벤트 처리
io.on('connection', (socket) => {
  // 방 참가
  socket.on('join', ({ token, nickname }) => {
    if (!token || !roomExistsAndActive(token)) {
      socket.emit('error_message', '유효하지 않거나 만료된 링크입니다.');
      return;
    }
    socket.join(token);
    socket.data.token = token;
    socket.data.nickname = nickname || '';

    const count = io.sockets.adapter.rooms.get(token)?.size || 1;
    io.to(token).emit('room_info', { count });
  });

  // 위치 업데이트 브로드캐스트
  socket.on('loc_update', (payload) => {
    const token = socket.data.token;
    if (!token) return;
    // payload: { lat, lng, accuracy, heading, speed, ts }
    io.to(token).emit('peer_loc', {
      id: socket.id,
      nickname: socket.data.nickname || '',
      ...payload,
    });
  });

  // 퇴장
  socket.on('disconnect', () => {
    const token = socket.data.token;
    if (!token) return;
    io.to(token).emit('peer_left', { id: socket.id });
    const count = io.sockets.adapter.rooms.get(token)?.size || 0;
    io.to(token).emit('room_info', { count });
  });
});

server.listen(PORT, () => {
  console.log(`Server listening on ${PORT}`);
});