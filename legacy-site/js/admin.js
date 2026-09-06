// ===== SSA ADMIN PANEL =====

// DEFAULT CREDENTIALS (change in settings)
const DEFAULT_USER = 'admin';
const DEFAULT_PASS = 'sobhan1404';

let adminData = { podcasts: [], books: [] };

// ---- INIT ----
window.addEventListener('DOMContentLoaded', () => {
  checkAuthState();
  loadAdminData();
});

// ---- AUTH ----
function checkAuthState() {
  const logged = sessionStorage.getItem('ssa_admin_logged');
  if (logged === 'true') showPanel();
}

function adminLogin() {
  const u = document.getElementById('adminUser').value.trim();
  const p = document.getElementById('adminPass').value;
  const storedPass = localStorage.getItem('ssa_admin_pass') || DEFAULT_PASS;
  const storedUser = localStorage.getItem('ssa_admin_user') || DEFAULT_USER;
  if (u === storedUser && p === storedPass) {
    sessionStorage.setItem('ssa_admin_logged', 'true');
    document.getElementById('loginError').classList.add('hidden');
    showPanel();
  } else {
    document.getElementById('loginError').classList.remove('hidden');
    document.getElementById('adminPass').value = '';
  }
}

function adminLogout() {
  sessionStorage.removeItem('ssa_admin_logged');
  document.getElementById('adminPanel').classList.add('hidden');
  document.getElementById('loginScreen').classList.remove('hidden');
}

function showPanel() {
  document.getElementById('loginScreen').classList.add('hidden');
  document.getElementById('adminPanel').classList.remove('hidden');
  renderAll();
}

// ---- DATA ----
function loadAdminData() {
  const saved = localStorage.getItem('ssa_content');
  if (saved) {
    try {
      const p = JSON.parse(saved);
      adminData.podcasts = p.podcasts || window.SSAData.podcasts;
      adminData.books = p.books || window.SSAData.books;
    } catch(e) {
      adminData.podcasts = [...window.SSAData.podcasts];
      adminData.books = [...window.SSAData.books];
    }
  } else {
    adminData.podcasts = [...window.SSAData.podcasts];
    adminData.books = [...window.SSAData.books];
  }
}

function saveAdminData() {
  localStorage.setItem('ssa_content', JSON.stringify({ podcasts: adminData.podcasts, books: adminData.books }));
  showAdminToast('✅ تغییرات ذخیره شد');
}

// ---- RENDER ALL ----
function renderAll() {
  renderPodcastTable();
  renderBooksTable();
  updateDashboard();
}

function updateDashboard() {
  const pc = document.getElementById('dashPodCount');
  const bc = document.getElementById('dashBookCount');
  if (pc) pc.textContent = adminData.podcasts.length;
  if (bc) bc.textContent = adminData.books.length;
}

// ---- TABS ----
function switchTab(tab, btn) {
  document.querySelectorAll('.admin-tab').forEach(t => t.classList.remove('active'));
  document.querySelectorAll('.snav-btn').forEach(b => b.classList.remove('active'));
  document.getElementById('tab-' + tab).classList.add('active');
  btn.classList.add('active');
}

// ---- PODCAST TABLE ----
function renderPodcastTable() {
  const tbody = document.getElementById('podcastTableBody');
  if (!tbody) return;
  tbody.innerHTML = '';
  adminData.podcasts.forEach((pod, idx) => {
    const tr = document.createElement('tr');
    const hasSrc = pod.src && pod.src.trim() !== '';
    tr.innerHTML = `
      <td><strong>${pod.emoji || '🎙️'} ${pod.title}</strong></td>
      <td>${categoryLabel(pod.category)}</td>
      <td>${pod.duration}</td>
      <td class="td-src ${hasSrc ? 'has-src' : ''}">${hasSrc ? '✅ ' + pod.src.split('/').pop() : '❌ ندارد'}</td>
      <td>
        <div class="tbl-actions">
          <button class="tbl-btn edit" onclick="editPodcast(${idx})">ویرایش</button>
          <button class="tbl-btn del" onclick="deletePodcast(${idx})">حذف</button>
        </div>
      </td>
    `;
    tbody.appendChild(tr);
  });
}

// ---- BOOKS TABLE ----
function renderBooksTable() {
  const tbody = document.getElementById('booksTableBody');
  if (!tbody) return;
  tbody.innerHTML = '';
  adminData.books.forEach((book, idx) => {
    const tr = document.createElement('tr');
    const hasSrc = book.src && book.src.trim() !== '';
    tr.innerHTML = `
      <td><strong>${book.emoji || '📚'} ${book.title}</strong></td>
      <td>${book.author}</td>
      <td>${book.duration}</td>
      <td class="td-src ${hasSrc ? 'has-src' : ''}">${hasSrc ? '✅ ' + book.src.split('/').pop() : '❌ ندارد'}</td>
      <td>
        <div class="tbl-actions">
          <button class="tbl-btn edit" onclick="editBook(${idx})">ویرایش</button>
          <button class="tbl-btn del" onclick="deleteBook(${idx})">حذف</button>
        </div>
      </td>
    `;
    tbody.appendChild(tr);
  });
}

function categoryLabel(cat) {
  const map = { trading: '📈 ترید', psychology: '🧠 روانشناسی', analysis: '📊 تحلیل' };
  return map[cat] || cat;
}

// ---- PODCAST MODAL ----
function openPodcastModal(pod = null, idx = null) {
  document.getElementById('podModalTitle').textContent = pod ? 'ویرایش پادکست' : 'افزودن پادکست';
  document.getElementById('podId').value = idx !== null ? idx : '';
  document.getElementById('podTitle').value = pod?.title || '';
  document.getElementById('podDesc').value = pod?.description || '';
  document.getElementById('podCategory').value = pod?.category || 'trading';
  document.getElementById('podDuration').value = pod?.duration || '';
  document.getElementById('podViews').value = pod?.views || '';
  document.getElementById('podEmoji').value = pod?.emoji || '🎙️';
  document.getElementById('podSrc').value = pod?.src || '';
  document.getElementById('podcastModal').classList.remove('hidden');
}

function closePodcastModal() {
  document.getElementById('podcastModal').classList.add('hidden');
}

function editPodcast(idx) {
  openPodcastModal(adminData.podcasts[idx], idx);
}

function deletePodcast(idx) {
  if (!confirm('آیا از حذف این پادکست مطمئن هستید؟')) return;
  adminData.podcasts.splice(idx, 1);
  renderPodcastTable();
  updateDashboard();
  saveAdminData();
}

function savePodcast() {
  const title = document.getElementById('podTitle').value.trim();
  if (!title) { showAdminToast('⚠️ عنوان پادکست الزامی است'); return; }
  const pod = {
    id: 'p' + Date.now(),
    title,
    description: document.getElementById('podDesc').value.trim(),
    category: document.getElementById('podCategory').value,
    duration: document.getElementById('podDuration').value.trim() || '00:00',
    views: document.getElementById('podViews').value.trim() || '0',
    emoji: document.getElementById('podEmoji').value.trim() || '🎙️',
    src: document.getElementById('podSrc').value.trim(),
    author: 'سبحان صمدی'
  };
  const idx = document.getElementById('podId').value;
  if (idx !== '') {
    pod.id = adminData.podcasts[idx].id;
    adminData.podcasts[idx] = pod;
  } else {
    adminData.podcasts.push(pod);
  }
  closePodcastModal();
  renderPodcastTable();
  updateDashboard();
  saveAdminData();
}

// ---- BOOK MODAL ----
function openBookModal(book = null, idx = null) {
  document.getElementById('bookModalTitle').textContent = book ? 'ویرایش کتاب' : 'افزودن کتاب صوتی';
  document.getElementById('bookId').value = idx !== null ? idx : '';
  document.getElementById('bookTitle').value = book?.title || '';
  document.getElementById('bookAuthor').value = book?.author || '';
  document.getElementById('bookDuration').value = book?.duration || '';
  document.getElementById('bookEmoji').value = book?.emoji || '📚';
  document.getElementById('bookSrc').value = book?.src || '';
  document.getElementById('bookModal').classList.remove('hidden');
}

function closeBookModal() {
  document.getElementById('bookModal').classList.add('hidden');
}

function editBook(idx) {
  openBookModal(adminData.books[idx], idx);
}

function deleteBook(idx) {
  if (!confirm('آیا از حذف این کتاب مطمئن هستید؟')) return;
  adminData.books.splice(idx, 1);
  renderBooksTable();
  updateDashboard();
  saveAdminData();
}

function saveBook() {
  const title = document.getElementById('bookTitle').value.trim();
  if (!title) { showAdminToast('⚠️ عنوان کتاب الزامی است'); return; }
  const book = {
    id: 'b' + Date.now(),
    title,
    author: document.getElementById('bookAuthor').value.trim() || 'ناشناس',
    duration: document.getElementById('bookDuration').value.trim() || '0 ساعت',
    emoji: document.getElementById('bookEmoji').value.trim() || '📚',
    src: document.getElementById('bookSrc').value.trim()
  };
  const idx = document.getElementById('bookId').value;
  if (idx !== '') {
    book.id = adminData.books[idx].id;
    adminData.books[idx] = book;
  } else {
    adminData.books.push(book);
  }
  closeBookModal();
  renderBooksTable();
  updateDashboard();
  saveAdminData();
}

// ---- FILE UPLOAD ----
function handleFileUpload(files) {
  const list = document.getElementById('uploadList');
  Array.from(files).forEach(file => {
    const item = document.createElement('div');
    item.className = 'upload-item';
    const path = 'assets/audio/' + file.name;
    item.innerHTML = `
      <div>
        <strong>${file.name}</strong>
        <div class="upload-item-path">${path}</div>
      </div>
      <span style="color:var(--success);font-size:12px;">✅ آماده استفاده</span>
    `;
    list.prepend(item);
  });
  showAdminToast(`✅ ${files.length} فایل انتخاب شد — مسیر را در پادکست/کتاب وارد کنید`);
}

function handleDrop(e) {
  e.preventDefault();
  handleFileUpload(e.dataTransfer.files);
}

function setAudioPathFromFile(input, targetId) {
  if (input.files[0]) {
    document.getElementById(targetId).value = 'assets/audio/' + input.files[0].name;
  }
}

// ---- SETTINGS ----
function changePassword() {
  const oldP = document.getElementById('oldPass').value;
  const newP = document.getElementById('newPass').value;
  const newP2 = document.getElementById('newPass2').value;
  const storedPass = localStorage.getItem('ssa_admin_pass') || DEFAULT_PASS;
  if (oldP !== storedPass) { showAdminToast('⚠️ رمز عبور فعلی اشتباه است'); return; }
  if (newP.length < 6) { showAdminToast('⚠️ رمز جدید باید حداقل ۶ کاراکتر باشد'); return; }
  if (newP !== newP2) { showAdminToast('⚠️ رمزهای جدید مطابقت ندارند'); return; }
  localStorage.setItem('ssa_admin_pass', newP);
  document.getElementById('oldPass').value = '';
  document.getElementById('newPass').value = '';
  document.getElementById('newPass2').value = '';
  showAdminToast('✅ رمز عبور با موفقیت تغییر کرد');
}

function resetData() {
  if (!confirm('تمام تغییرات شما پاک می‌شود. آیا مطمئن هستید؟')) return;
  localStorage.removeItem('ssa_content');
  loadAdminData();
  renderAll();
  showAdminToast('✅ داده‌ها به حالت اولیه بازگشتند');
}

// ---- TOAST ----
let toastTimer = null;
function showAdminToast(msg) {
  const t = document.getElementById('aToast');
  t.textContent = msg;
  t.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => t.classList.remove('show'), 3000);
}
