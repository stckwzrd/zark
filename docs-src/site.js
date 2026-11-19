(function () {
  var root = document.documentElement
  var saved = null
  try { saved = localStorage.getItem("theme") } catch (e) {}
  if (saved) root.setAttribute("data-theme", saved)
  document.getElementById("theme").addEventListener("click", function () {
    var dark = root.getAttribute("data-theme") === "dark" || (!root.getAttribute("data-theme") && matchMedia("(prefers-color-scheme: dark)").matches)
    var next = dark ? "light" : "dark"
    root.setAttribute("data-theme", next)
    try { localStorage.setItem("theme", next) } catch (e) {}
  })
  document.querySelector(".menu").addEventListener("click", function () { document.body.classList.toggle("nav-open") })
  var q = document.getElementById("q")
  var box = document.getElementById("results")
  var index = null
  function load(cb) {
    if (index) return cb()
    fetch("search-index.json").then(function (r) { return r.json() }).then(function (j) { index = j; cb() })
  }
  function run() {
    var terms = q.value.toLowerCase().split(/\s+/).filter(Boolean)
    if (!terms.length) { box.style.display = "none"; return }
    var hits = []
    index.forEach(function (p) {
      var score = 0, anchor = ""
      terms.forEach(function (t) {
        if (p.title.toLowerCase().indexOf(t) >= 0) score += 10
        p.headings.forEach(function (h) { if (h.text.toLowerCase().indexOf(t) >= 0) { score += 6; if (!anchor) anchor = h.id } })
        var k = p.text.toLowerCase().indexOf(t)
        if (k >= 0) score += 1
      })
      if (score > 0) hits.push({ p: p, score: score, anchor: anchor })
    })
    hits.sort(function (a, b) { return b.score - a.score })
    box.innerHTML = hits.slice(0, 8).map(function (h) {
      return '<a href="' + h.p.url + (h.anchor ? "#" + h.anchor : "") + '"><b>' + h.p.title + "</b></a>"
    }).join("") || "<span>Ничего не найдено</span>"
    box.style.display = "block"
  }
  q.addEventListener("input", function () { load(run) })
  q.addEventListener("focus", function () { if (q.value) load(run) })
  document.addEventListener("click", function (e) { if (!e.target.closest(".search")) box.style.display = "none" })
  document.addEventListener("keydown", function (e) {
    if (e.key === "/" && document.activeElement !== q) { e.preventDefault(); q.focus() }
  })
  var links = document.querySelectorAll(".toc a")
  if (links.length && "IntersectionObserver" in window) {
    var map = {}
    links.forEach(function (a) { map[a.getAttribute("href").slice(1)] = a })
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        if (en.isIntersecting) {
          links.forEach(function (a) { a.classList.remove("on") })
          var a = map[en.target.id]
          if (a) a.classList.add("on")
        }
      })
    }, { rootMargin: "0px 0px -75% 0px" })
    document.querySelectorAll("article h2[id], article h3[id]").forEach(function (h) { io.observe(h) })
  }
  document.querySelectorAll(".code").forEach(function (c) {
    var b = document.createElement("button")
    b.className = "copy"
    b.textContent = "Копировать"
    b.addEventListener("click", function () {
      var t = c.querySelector("pre").innerText
      if (navigator.clipboard) navigator.clipboard.writeText(t)
      b.textContent = "Скопировано"
      setTimeout(function () { b.textContent = "Копировать" }, 1200)
    })
    c.appendChild(b)
  })
})()
