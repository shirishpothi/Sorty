/* Sorty site — nav behaviour, scroll reveal, copy install command, active release nav */
(function () {
  'use strict';

  /* ---- Whimsy-style pixel loader ---- */
  var loader = document.createElement('div');
  loader.className = 'site-loader';
  loader.setAttribute('role', 'status');
  loader.setAttribute('aria-live', 'polite');
  loader.innerHTML = '<canvas class="site-loader-canvas" width="48" height="48" aria-hidden="true"></canvas><span>sorting things out</span>';
  document.body.appendChild(loader);

  var loaderCanvas = loader.querySelector('canvas');
  var loaderContext = loaderCanvas && loaderCanvas.getContext('2d');
  var loaderStart = window.performance ? performance.now() : Date.now();
  var loaderFrame = null;
  var loaderReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var loaderColor = { r: 95, g: 179, b: 255 };
  var loaderDots = [
    [-4, -1], [-3, -1], [-2, -1], [-1, -1], [0, -1], [1, -1], [2, -1], [3, -1], [4, -1],
    [-4, 0], [-3, 0], [-2, 0], [-1, 0], [0, 0], [1, 0], [2, 0], [3, 0], [4, 0],
    [-3, 1], [-2, 1], [-1, 1], [0, 1], [1, 1], [2, 1], [3, 1],
    [-2, 2], [-1, 2], [0, 2], [1, 2], [2, 2],
    [-1, 3], [0, 3], [1, 3], [0, 4]
  ];

  function loaderRGBA(alpha) {
    return 'rgba(' + loaderColor.r + ',' + loaderColor.g + ',' + loaderColor.b + ',' + alpha + ')';
  }

  function drawLoader(time) {
    if (!loaderContext) return;
    var size = 48;
    var scale = 3;
    var center = size / 2;
    loaderContext.clearRect(0, 0, size, size);
    loaderDots.forEach(function (dot, index) {
      var distance = Math.hypot(dot[0], dot[1]);
      var wave = loaderReducedMotion ? 0.7 : Math.max(0, Math.sin(time * 0.0022 - distance * 0.32 + index * 0.04));
      var alpha = 0.14 + 0.76 * wave * wave;
      loaderContext.fillStyle = loaderRGBA(alpha);
      loaderContext.fillRect(
        Math.round(center + dot[0] * scale),
        Math.round(center + dot[1] * scale),
        scale,
        scale
      );
    });
  }

  function tickLoader(now) {
    drawLoader(now - loaderStart);
    if (!loaderReducedMotion) {
      loaderFrame = window.requestAnimationFrame(tickLoader);
    }
  }

  if (loaderContext) {
    tickLoader(loaderStart);
  }

  function finishLoader() {
    window.setTimeout(function () {
      loader.classList.add('is-hidden');
      if (loaderFrame) window.cancelAnimationFrame(loaderFrame);
      window.setTimeout(function () {
        if (loader.parentNode) loader.parentNode.removeChild(loader);
      }, 420);
    }, 180);
  }

  if (document.readyState === 'complete') {
    finishLoader();
  } else {
    window.addEventListener('load', finishLoader, { once: true });
  }

  /* ---- Mobile nav toggle ---- */
  var nav = document.querySelector('.nav');
  var toggle = document.querySelector('.nav-toggle');
  if (toggle && nav) {
    toggle.addEventListener('click', function () {
      nav.classList.toggle('open');
      var expanded = nav.classList.contains('open');
      toggle.setAttribute('aria-expanded', String(expanded));
    });
    nav.querySelectorAll('.nav-links a').forEach(function (a) {
      a.addEventListener('click', function () { nav.classList.remove('open'); });
    });
  }

  /* ---- Hide nav on scroll-down, show on scroll-up ---- */
  var last = 0;
  var ticking = false;
  function onScroll() {
    var y = window.pageYOffset;
    if (!nav) { ticking = false; return; }
    if (y > 200 && y > last) {
      nav.classList.add('hidden');
      nav.classList.remove('open');
    } else {
      nav.classList.remove('hidden');
    }
    last = y;
    ticking = false;
  }
  window.addEventListener('scroll', function () {
    if (!ticking) { window.requestAnimationFrame(onScroll); ticking = true; }
  }, { passive: true });

  /* ---- Reveal on scroll (IntersectionObserver) ---- */
  var reveals = document.querySelectorAll('.reveal, .reveal-scale');
  if ('IntersectionObserver' in window && reveals.length) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); }
      });
    }, { threshold: 0.12, rootMargin: '0px 0px -40px 0px' });
    reveals.forEach(function (el) { io.observe(el); });
  } else {
    reveals.forEach(function (el) { el.classList.add('in'); });
  }

  /* ---- Hero shot: scroll-driven blur & scale (whimsically-style parallax) ---- */
  var heroShot = document.getElementById('hero-shot');
  var reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  if (heroShot && !reduceMotion) {
    var img = heroShot.querySelector('img');
    var ticking2 = false;
    function onHeroScroll() {
      var y = window.pageYOffset;
      var progress = Math.min(y / Math.max(1, window.innerHeight * 0.9), 1);
      // scale 1.00 -> 1.08, slight upward parallax, blur clears quickly
      var scale = 1 + progress * 0.08;
      var ty = -progress * 40;
      heroShot.style.transform = 'translate3d(0,' + ty.toFixed(1) + 'px,0) scale(' + scale.toFixed(4) + ')';
      if (img) { img.style.transform = 'scale(' + (1 - progress * 0.02).toFixed(4) + ')'; }
      ticking2 = false;
    }
    window.addEventListener('scroll', function () {
      if (!ticking2) { window.requestAnimationFrame(onHeroScroll); ticking2 = true; }
    }, { passive: true });
    onHeroScroll();
  }

  /* ---- Copy install command ---- */
  document.querySelectorAll('[data-copy]').forEach(function (btn) {
    btn.addEventListener('click', function () {
      var text = btn.getAttribute('data-copy') || '';
      var label = btn.querySelector('.copy-label');
      var done = function () {
        if (label) { var old = label.textContent; label.textContent = 'Copied!'; setTimeout(function () { label.textContent = old; }, 1600); }
      };
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(done).catch(function () { fallback(text, done); });
      } else { fallback(text, done); }
    });
  });
  function fallback(text, cb) {
    var t = document.createElement('textarea'); t.value = text; t.style.position = 'fixed'; t.style.opacity = '0';
    document.body.appendChild(t); t.select();
    try { document.execCommand('copy'); cb(); } catch (e) {}
    document.body.removeChild(t);
  }

  /* ---- Active release nav on changelog ---- */
  var navLinks = document.querySelectorAll('.release-nav a');
  var releases = document.querySelectorAll('.release');
  if (navLinks.length && releases.length && 'IntersectionObserver' in window) {
    var ro = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting) {
          var id = e.target.getAttribute('id');
          navLinks.forEach(function (a) {
            a.classList.toggle('active', a.getAttribute('href') === '#' + id);
          });
        }
      });
    }, { rootMargin: '-30% 0px -60% 0px' });
    releases.forEach(function (r) { ro.observe(r); });
  }

  /* ---- Smooth scroll for in-page anchors (respect reduced motion) ---- */
  if (!window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
    document.querySelectorAll('a[href^="#"]').forEach(function (a) {
      a.addEventListener('click', function (ev) {
        var id = a.getAttribute('href');
        if (id.length < 2) return;
        var el = document.querySelector(id);
        if (el) { ev.preventDefault(); el.scrollIntoView({ behavior: 'smooth', block: 'start' }); }
      });
    });
  }
})();
