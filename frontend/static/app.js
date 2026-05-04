// Car Insurance AI — Frontend chat client
const chatWindow = document.getElementById('chatWindow');
const chatForm = document.getElementById('chatForm');
const messageInput = document.getElementById('messageInput');
const sendBtn = document.getElementById('sendBtn');
const fileInput = document.getElementById('fileInput');
const uploadBtn = document.getElementById('uploadBtn');
const imagePreview = document.getElementById('imagePreview');
const agentIndicator = document.getElementById('agentIndicator');

let sessionId = localStorage.getItem('ci_session_id') || null;
let pendingImage = null;

// ─── Suggestions ────────────────────────────────────────────────────────────
document.querySelectorAll('.suggestion').forEach(btn => {
  btn.addEventListener('click', () => {
    messageInput.value = btn.dataset.msg;
    chatForm.dispatchEvent(new Event('submit'));
  });
});

// ─── File upload ────────────────────────────────────────────────────────────
uploadBtn.addEventListener('click', () => fileInput.click());

fileInput.addEventListener('change', (e) => {
  const file = e.target.files[0];
  if (!file) return;
  if (!file.type.startsWith('image/')) {
    alert('Please upload an image file');
    return;
  }
  if (file.size > 10 * 1024 * 1024) {
    alert('Image too large (max 10MB)');
    return;
  }
  const reader = new FileReader();
  reader.onload = (ev) => {
    pendingImage = ev.target.result.split(',')[1];   // strip data: prefix
    imagePreview.innerHTML = `
      <img src="${ev.target.result}" alt="damage" />
      <span class="filename">${file.name}</span>
      <button class="remove-img" onclick="clearImage()">×</button>
    `;
    imagePreview.classList.add('active');
    messageInput.placeholder = "Describe the incident, then send...";
  };
  reader.readAsDataURL(file);
});

window.clearImage = () => {
  pendingImage = null;
  imagePreview.innerHTML = '';
  imagePreview.classList.remove('active');
  fileInput.value = '';
  messageInput.placeholder = "Ask about quotes, claims, or policy questions...";
};

// ─── Send message ───────────────────────────────────────────────────────────
chatForm.addEventListener('submit', async (e) => {
  e.preventDefault();
  const message = messageInput.value.trim();
  if (!message && !pendingImage) return;

  // Render user bubble
  addMessage(message || '[uploaded damage photo]', 'user');
  messageInput.value = '';
  sendBtn.disabled = true;
  messageInput.disabled = true;

  // Show typing indicator
  const typingMsg = addTypingIndicator();

  // Capture image if present, then clear preview
  const imageToSend = pendingImage;
  if (imageToSend) clearImage();

  try {
    const resp = await fetch('/api/chat', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        message,
        session_id: sessionId,
        damage_image_b64: imageToSend,
      }),
    });

    if (!resp.ok) {
      const err = await resp.text();
      throw new Error(`HTTP ${resp.status}: ${err}`);
    }
    const data = await resp.json();

    sessionId = data.session_id;
    localStorage.setItem('ci_session_id', sessionId);

    typingMsg.remove();
    addMessage(data.reply, 'bot', data.tool_calls);
    updateAgentIndicator(data.intent);
  } catch (err) {
    typingMsg.remove();
    addMessage(`⚠️ Error: ${err.message}`, 'bot');
  } finally {
    sendBtn.disabled = false;
    messageInput.disabled = false;
    messageInput.focus();
  }
});

// ─── Rendering ──────────────────────────────────────────────────────────────
function addMessage(text, role, toolCalls = []) {
  const msg = document.createElement('div');
  msg.className = `message ${role}`;

  const bubble = document.createElement('div');
  bubble.className = 'bubble';
  bubble.textContent = text;
  msg.appendChild(bubble);

  if (toolCalls && toolCalls.length > 0) {
    const trace = document.createElement('div');
    trace.className = 'tool-trace';
    const names = toolCalls.map(t => `🔧 ${t.name}`).join('  ·  ');
    trace.textContent = names;
    msg.appendChild(trace);
  }

  chatWindow.appendChild(msg);
  chatWindow.scrollTop = chatWindow.scrollHeight;
  return msg;
}

function addTypingIndicator() {
  const msg = document.createElement('div');
  msg.className = 'message bot';
  const bubble = document.createElement('div');
  bubble.className = 'bubble';
  bubble.innerHTML = '<div class="typing"><span></span><span></span><span></span></div>';
  msg.appendChild(bubble);
  chatWindow.appendChild(msg);
  chatWindow.scrollTop = chatWindow.scrollHeight;
  return msg;
}

function updateAgentIndicator(intent) {
  const map = {
    quote: { name: 'Quote Agent', color: '#8DC63F' },
    claim: { name: 'Claims Agent', color: '#F39C12' },
    policy_qa: { name: 'Policy Q&A Agent', color: '#1B9BD9' },
  };
  const info = map[intent] || { name: 'Routing…', color: '#8DC63F' };
  agentIndicator.querySelector('.agent-name').textContent = info.name;
  agentIndicator.querySelector('.agent-dot').style.background = info.color;
}

// Focus input on load
messageInput.focus();
