// ===== SSA AUDIO PLAYER ENGINE =====

let currentTrack = null;
let playlist = [];
let currentIndex = 0;
let isPlaying = false;
let playbackSpeed = 1;
let isLoop = false;
let audioCtx = null;
let analyser = null;
let sourceNode = null;
let animFrame = null;

const audio = document.getElementById('mainAudio');

// ---- INIT AUDIO CONTEXT ----
function initAudioContext() {
  if (audioCtx) return;
  audioCtx = new (window.AudioContext || window.webkitAudioContext)();
  analyser = audioCtx.createAnalyser();
  analyser.fftSize = 256;
  sourceNode = audioCtx.createMediaElementSource(audio);
  sourceNode.connect(analyser);
  analyser.connect(audioCtx.destination);
}

// ---- LOAD TRACK ----
function loadTrack(track, autoplay = true) {
  currentTrack = track;
  const hasSrc = track.src && track.src.trim() !== '';

  // Update featured player UI
  document.getElementById('fpTitle').textContent = track.title;
  document.getElementById('fpAuthor').textContent = track.author || 'سبحان صمدی';

  // Update mini player
  document.getElementById('mpTitle').textContent = track.title;
  document.getElementById('mpAuthor').textContent = track.author || 'سبحان صمدی';

  // Mark active card
  document.querySelectorAll('.audio-card').forEach(c => {
    c.classList.toggle('active', c.dataset.id === track.id);
  });

  if (hasSrc) {
    audio.src = track.src;
    audio.load();
    if (autoplay) {
      audio.play().then(() => {
        setPlayState(true);
        initAudioContext();
        drawWaveform();
      }).catch(() => showToast('خطا در پخش فایل صوتی'));
    }
  } else {
    // Demo mode - animate waveform without audio
    setPlayState(autoplay);
    if (autoplay) {
      simulateWaveform();
      simulateProgress();
    }
    showToast('فایل صوتی هنوز بارگذاری نشده — پنل مدیریت را بررسی کنید');
  }

  // Show mini player
  document.getElementById('miniPlayer').classList.add('visible');

  // Scroll to featured player
  document.getElementById('featured').scrollIntoView({ behavior: 'smooth', block: 'start' });
}

// ---- PLAY/PAUSE ----
function toggleMainPlay() {
  if (!currentTrack) {
    if (playlist.length > 0) loadTrack(playlist[0]);
    return;
  }
  const hasSrc = currentTrack.src && currentTrack.src.trim() !== '';
  if (hasSrc) {
    if (isPlaying) audio.pause();
    else { audio.play(); initAudioContext(); drawWaveform(); }
  } else {
    setPlayState(!isPlaying);
    if (!isPlaying) { simulateWaveform(); simulateProgress(); }
  }
}

function setPlayState(playing) {
  isPlaying = playing;
  // Featured play button
  const fp = document.getElementById('mainPlayBtn');
  if (fp) {
    fp.querySelector('.play-icon').classList.toggle('hidden', playing);
    fp.querySelector('.pause-icon').classList.toggle('hidden', !playing);
  }
  // Artwork overlay button
  const fpBig = document.getElementById('fpPlayBtn');
  if (fpBig) fpBig.innerHTML = playing
    ? '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z"/></svg>'
    : '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z"/></svg>';
  // Mini player
  const mp = document.getElementById('mpPlayBtn');
  if (mp) mp.textContent = playing ? '⏸' : '▶';
}

// ---- SKIP ----
function skipForward() {
  if (currentTrack?.src) audio.currentTime = Math.min(audio.currentTime + 15, audio.duration || 0);
  else showToast('+۱۵ ثانیه');
}
function skipBackward() {
  if (currentTrack?.src) audio.currentTime = Math.max(audio.currentTime - 15, 0);
  else showToast('-۱۵ ثانیه');
}

// ---- NEXT/PREV ----
function nextTrack() {
  if (playlist.length === 0) return;
  currentIndex = (currentIndex + 1) % playlist.length;
  loadTrack(playlist[currentIndex]);
}
function prevTrack() {
  if (playlist.length === 0) return;
  currentIndex = (currentIndex - 1 + playlist.length) % playlist.length;
  loadTrack(playlist[currentIndex]);
}

// ---- SPEED ----
function cycleSpeed() {
  const speeds = [1, 1.25, 1.5, 1.75, 2, 0.75];
  const idx = speeds.indexOf(playbackSpeed);
  playbackSpeed = speeds[(idx + 1) % speeds.length];
  audio.playbackRate = playbackSpeed;
  document.getElementById('speedBtn').textContent = `سرعت: ${playbackSpeed}×`;
}

// ---- LOOP ----
function toggleLoop() {
  isLoop = !isLoop;
  audio.loop = isLoop;
  document.getElementById('loopBtn').classList.toggle('active', isLoop);
  showToast(isLoop ? 'تکرار فعال شد' : 'تکرار غیرفعال شد');
}

// ---- VOLUME ----
function setVolume(val) {
  audio.volume = val;
}

// ---- SEEK ----
function seekAudio(e) {
  const bar = document.getElementById('fpProgressBar');
  const rect = bar.getBoundingClientRect();
  // RTL: progress fills from right to left for Arabic-style, but audio time is LTR
  const pct = (e.clientX - rect.left) / rect.width;
  if (currentTrack?.src && audio.duration) {
    audio.currentTime = pct * audio.duration;
  }
}

// ---- AUDIO EVENTS ----
audio.addEventListener('timeupdate', () => {
  const pct = audio.duration ? (audio.currentTime / audio.duration) * 100 : 0;
  updateProgress(pct);
  document.getElementById('fpCurrent').textContent = formatTime(audio.currentTime);
  document.getElementById('fpDuration').textContent = formatTime(audio.duration || 0);
});
audio.addEventListener('play', () => setPlayState(true));
audio.addEventListener('pause', () => setPlayState(false));
audio.addEventListener('ended', () => {
  if (!isLoop) nextTrack();
  else audio.play();
});
audio.addEventListener('loadedmetadata', () => {
  document.getElementById('fpDuration').textContent = formatTime(audio.duration);
});

function updateProgress(pct) {
  document.getElementById('fpProgressFill').style.width = pct + '%';
  document.getElementById('fpProgressThumb').style.right = pct + '%';
  document.getElementById('mpProgressFill').style.width = pct + '%';
}

// ---- WAVEFORM CANVAS ----
function drawWaveform() {
  if (!analyser) return;
  const canvas = document.getElementById('waveCanvas');
  const ctx = canvas.getContext('2d');
  const bufLen = analyser.frequencyBinCount;
  const dataArr = new Uint8Array(bufLen);

  function draw() {
    animFrame = requestAnimationFrame(draw);
    analyser.getByteFrequencyData(dataArr);
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    const barW = (canvas.width / bufLen) * 2;
    let x = 0;
    for (let i = 0; i < bufLen; i++) {
      const barH = (dataArr[i] / 255) * canvas.height;
      const alpha = 0.5 + (dataArr[i] / 255) * 0.5;
      ctx.fillStyle = `rgba(200,168,75,${alpha})`;
      ctx.fillRect(x, canvas.height - barH, barW - 1, barH);
      x += barW;
    }
  }
  draw();
}

// ---- SIMULATE WAVEFORM (demo mode) ----
let simWaveInterval = null;
function simulateWaveform() {
  if (simWaveInterval) clearInterval(simWaveInterval);
  const canvas = document.getElementById('waveCanvas');
  const ctx = canvas.getContext('2d');
  const bars = 50;
  simWaveInterval = setInterval(() => {
    if (!isPlaying) return;
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    const barW = canvas.width / bars - 2;
    for (let i = 0; i < bars; i++) {
      const h = (0.2 + Math.random() * 0.8) * canvas.height;
      const alpha = 0.4 + Math.random() * 0.6;
      ctx.fillStyle = `rgba(200,168,75,${alpha})`;
      ctx.fillRect(i * (barW + 2), canvas.height - h, barW, h);
    }
  }, 80);
}

let simProgressInterval = null;
let simProgress = 0;
function simulateProgress() {
  if (simProgressInterval) clearInterval(simProgressInterval);
  simProgressInterval = setInterval(() => {
    if (!isPlaying) return;
    simProgress = Math.min(simProgress + 0.05, 100);
    updateProgress(simProgress);
    const totalSec = 2700; // 45min demo
    const elapsed = (simProgress / 100) * totalSec;
    document.getElementById('fpCurrent').textContent = formatTime(elapsed);
    document.getElementById('fpDuration').textContent = '۴۵:۰۰';
    if (simProgress >= 100) { simProgress = 0; nextTrack(); }
  }, 1000);
}

// ---- UTILS ----
function formatTime(secs) {
  if (!secs || isNaN(secs)) return '۰:۰۰';
  const m = Math.floor(secs / 60);
  const s = Math.floor(secs % 60);
  return `${m}:${s.toString().padStart(2, '0')}`;
}

let toastTimer = null;
function showToast(msg) {
  const t = document.getElementById('toast');
  t.textContent = msg;
  t.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => t.classList.remove('show'), 3000);
}
