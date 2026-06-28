// ===== SSA MAIN APP =====

document.addEventListener('DOMContentLoaded', () => {
  renderPodcasts();
  renderBooks();
  renderTestimonials();
  setupNavbar();
  setupHamburger();
  setupFilters();
  setupFilterTabs();
  loadFeaturedTrack();
});

// ---- RENDER PODCASTS ----
function renderPodcasts(filter = 'all') {
  const grid = document.getElementById('podcastGrid');
  if (!grid) return;
  const data = window.SSAData.podcasts;
  const filtered = filter === 'all' ? data : data.filter(p => p.category === filter);

  grid.innerHTML = '';
  playlist = filtered;

  filtered.forEach((item, idx) => {
    const card = document.createElement('div');
    card.className = 'audio-card';
    card.dataset.id = item.id;
    card.innerHTML = `
      <div class="card-artwork">
        <div class="card-artwork-emoji" style="height:180px;display:flex;align-items:center;justify-content:center;background:linear-gradient(135deg,#141f38,#0d1526);font-size:80px">${item.emoji || '🎙️'}</div>
        <div class="card-overlay"></div>
        <button class="card-play-btn" onclick="handleCardPlay(event,'${item.id}')">
          <svg viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z"/></svg>
        </button>
        <span class="card-duration-badge">${item.duration}</span>
      </div>
      <div class="card-body">
        <div class="card-category">${categoryLabel(item.category)}</div>
        <div class="card-title">${item.title}</div>
        <div class="card-desc">${item.description}</div>
        <div class="card-meta">
          <div class="card-author"><div class="card-author-dot"></div>${item.author}</div>
          <div class="card-views">👁 ${item.views}</div>
        </div>
      </div>
    `;
    card.addEventListener('click', (e) => {
      if (!e.target.closest('.card-play-btn')) handleCardPlay(e, item.id);
    });
    grid.appendChild(card);
  });
}

function handleCardPlay(e, id) {
  e && e.stopPropagation();
  const item = window.SSAData.podcasts.find(p => p.id === id) || window.SSAData.books.find(b => b.id === id);
  if (!item) return;
  currentIndex = playlist.findIndex(p => p.id === id);
  simProgress = 0;
  loadTrack(item, true);
}

function categoryLabel(cat) {
  const map = { trading: '📈 ترید', psychology: '🧠 روانشناسی', analysis: '📊 تحلیل', book: '📚 کتاب' };
  return map[cat] || cat;
}

// ---- RENDER BOOKS ----
function renderBooks() {
  const grid = document.getElementById('booksGrid');
  if (!grid) return;
  window.SSAData.books.forEach(book => {
    const card = document.createElement('div');
    card.className = 'book-card';
    card.innerHTML = `
      <div class="book-cover">
        <div class="book-cover-inner">${book.emoji || '📚'}</div>
      </div>
      <div class="book-body">
        <div class="book-title">${book.title}</div>
        <div class="book-author">${book.author}</div>
        <div class="book-play-row">
          <button class="book-play-btn" onclick="playBook('${book.id}')">
            ▶ پخش
          </button>
          <span class="book-duration">${book.duration}</span>
        </div>
      </div>
    `;
    grid.appendChild(card);
  });
}

function playBook(id) {
  const book = window.SSAData.books.find(b => b.id === id);
  if (!book) return;
  playlist = window.SSAData.books;
  currentIndex = window.SSAData.books.findIndex(b => b.id === id);
  simProgress = 0;
  loadTrack({ ...book, category: 'book' }, true);
}

// ---- RENDER TESTIMONIALS ----
function renderTestimonials() {
  const inner = document.getElementById('testimonialsInner');
  if (!inner) return;
  const all = [...window.SSAData.testimonials, ...window.SSAData.testimonials]; // duplicate for infinite scroll
  inner.innerHTML = '';
  all.forEach(t => {
    const card = document.createElement('div');
    card.className = 'testimonial-card';
    card.innerHTML = `
      <div class="t-stars">${'⭐'.repeat(t.rating)}</div>
      <div class="t-text">"${t.text}"</div>
      <div class="t-author">
        <div class="t-avatar">${t.initial}</div>
        <div>
          <div class="t-name">${t.name}</div>
          <div class="t-role">${t.role}</div>
        </div>
      </div>
    `;
    inner.appendChild(card);
  });
}

// ---- LOAD FEATURED TRACK ----
function loadFeaturedTrack() {
  if (window.SSAData.podcasts.length > 0) {
    const first = window.SSAData.podcasts[0];
    playlist = window.SSAData.podcasts;
    currentIndex = 0;
    currentTrack = first;
    document.getElementById('fpTitle').textContent = first.title;
    document.getElementById('fpAuthor').textContent = first.author;
  }
}

// ---- NAVBAR SCROLL ----
function setupNavbar() {
  window.addEventListener('scroll', () => {
    document.getElementById('navbar').classList.toggle('scrolled', window.scrollY > 60);
  });
}

// ---- HAMBURGER ----
function setupHamburger() {
  const btn = document.getElementById('hamburger');
  const menu = document.getElementById('mobileMenu');
  if (!btn || !menu) return;
  btn.addEventListener('click', () => menu.classList.toggle('open'));
  menu.querySelectorAll('a').forEach(a => a.addEventListener('click', () => menu.classList.remove('open')));
}

// ---- FILTER TABS ----
function setupFilterTabs() {
  document.querySelectorAll('.filter-tab').forEach(tab => {
    tab.addEventListener('click', () => {
      document.querySelectorAll('.filter-tab').forEach(t => t.classList.remove('active'));
      tab.classList.add('active');
      renderPodcasts(tab.dataset.filter);
    });
  });
}

function setupFilters() {
  // Smooth scroll for anchors
  document.querySelectorAll('a[href^="#"]').forEach(a => {
    a.addEventListener('click', e => {
      const target = document.querySelector(a.getAttribute('href'));
      if (target) { e.preventDefault(); target.scrollIntoView({ behavior: 'smooth' }); }
    });
  });
}

// ---- CONTACT FORM ----
function submitContact() {
  showToast('✅ پیام شما ارسال شد. به زودی با شما تماس می‌گیریم.');
}
