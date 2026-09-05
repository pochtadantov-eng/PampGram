/* PampGram · landing interactions */

(() => {
  'use strict';

  /* ── mobile nav toggle ── */
  const nav = document.getElementById('site-nav');
  const toggle = document.querySelector('.nav-toggle');
  if (nav && toggle) {
    toggle.addEventListener('click', () => {
      const open = nav.classList.toggle('is-open');
      toggle.setAttribute('aria-expanded', open ? 'true' : 'false');
    });
    nav.addEventListener('click', (e) => {
      if (e.target.tagName === 'A') {
        nav.classList.remove('is-open');
        toggle.setAttribute('aria-expanded', 'false');
      }
    });
  }

  /* ── catalog filter ── */
  const tabs  = document.querySelectorAll('.catalog__filter .chip--tab');
  const cards = document.querySelectorAll('.cat-card');
  tabs.forEach(tab => {
    tab.addEventListener('click', () => {
      tabs.forEach(t => {
        t.classList.remove('is-active');
        t.setAttribute('aria-selected', 'false');
      });
      tab.classList.add('is-active');
      tab.setAttribute('aria-selected', 'true');
      const f = tab.dataset.filter;
      cards.forEach(c => {
        c.hidden = !(f === 'all' || c.dataset.cat === f);
      });
    });
  });

  /* ── subscribe form ── */
  const form = document.getElementById('subscribe-form');
  const status = document.getElementById('form-status');
  if (form && status) {
    form.addEventListener('submit', (e) => {
      e.preventDefault();
      status.className = 'form__status';
      if (!form.checkValidity()) {
        status.textContent = 'Проверь обязательные поля.';
        status.classList.add('is-err');
        return;
      }
      const data = new FormData(form);
      const topics = data.getAll('topics').join(', ') || '—';
      status.textContent = `Готово, ${data.get('name')}! Отправим на ${data.get('email')}. Темы: ${topics}.`;
      status.classList.add('is-ok');
      form.reset();
    });
  }

  /* ── active nav link on scroll ── */
  const sections = document.querySelectorAll('section[id]');
  const links = document.querySelectorAll('.site-nav__list a');
  if ('IntersectionObserver' in window && sections.length && links.length) {
    const io = new IntersectionObserver((entries) => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          const id = entry.target.id;
          links.forEach(a => {
            a.style.color = a.getAttribute('href') === `#${id}` ? 'var(--text)' : '';
          });
        }
      });
    }, { rootMargin: '-40% 0px -55% 0px' });
    sections.forEach(s => io.observe(s));
  }
})();
