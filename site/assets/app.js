// moonlog — a site with no build step. Everything here is progressive: the
// pages read and navigate without it, and it adds the theme switch, the tabs,
// the copy buttons and the stream in the hero.

(function () {
  "use strict";

  var root = document.documentElement;
  var reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  // ?theme=light or ?theme=dark pins a theme for a shared link or a screenshot.
  var asked = /[?&]theme=(light|dark)/.exec(location.search);
  if (asked) {
    root.setAttribute("data-theme", asked[1]);
  }

  // ---------------------------------------------------------------- theme
  function setTheme(name) {
    root.setAttribute("data-theme", name);
    try {
      localStorage.setItem("moonlog-theme", name);
    } catch (e) {
      /* private mode */
    }
  }

  document.querySelectorAll("[data-theme-toggle]").forEach(function (button) {
    button.addEventListener("click", function () {
      setTheme(root.getAttribute("data-theme") === "dark" ? "light" : "dark");
    });
  });

  // ----------------------------------------------------------------- copy
  document.querySelectorAll("[data-copy]").forEach(function (button) {
    button.addEventListener("click", function () {
      var block = button.closest(".code");
      var text = block ? block.querySelector("pre").innerText : "";
      var done = function () {
        var was = button.textContent;
        button.textContent = "copied";
        setTimeout(function () {
          button.textContent = was;
        }, 1400);
      };
      if (navigator.clipboard) {
        navigator.clipboard.writeText(text).then(done, done);
      }
    });
  });

  // ----------------------------------------------------------------- tabs
  document.querySelectorAll("[data-tabs]").forEach(function (group) {
    var buttons = group.querySelectorAll("[role=tab]");
    buttons.forEach(function (button) {
      button.addEventListener("click", function () {
        buttons.forEach(function (other) {
          other.setAttribute("aria-selected", other === button ? "true" : "false");
          var panel = document.getElementById(other.getAttribute("aria-controls"));
          if (panel) panel.classList.toggle("on", other === button);
        });
      });
    });
  });

  // ------------------------------------------------------------ api filter
  var search = document.querySelector("[data-api-filter]");
  if (search) {
    var entries = Array.prototype.slice.call(document.querySelectorAll("[data-api-entry]"));
    var count = document.querySelector("[data-api-count]");
    var heads = Array.prototype.slice.call(document.querySelectorAll("[data-api-group]"));
    var apply = function () {
      var q = search.value.trim().toLowerCase();
      var shown = 0;
      entries.forEach(function (entry) {
        var hit = q === "" || entry.getAttribute("data-api-entry").toLowerCase().indexOf(q) !== -1;
        entry.style.display = hit ? "" : "none";
        if (hit) shown++;
      });
      heads.forEach(function (head) {
        var any = false;
        var node = head.nextElementSibling;
        while (node && !node.hasAttribute("data-api-group")) {
          if (node.hasAttribute("data-api-entry") && node.style.display !== "none") any = true;
          node = node.nextElementSibling;
        }
        head.style.display = any ? "" : "none";
      });
      if (count) count.textContent = shown + " / " + entries.length;
    };
    search.addEventListener("input", apply);
    apply();
  }

  // ------------------------------------------------------------ scrollspy
  var rail = document.querySelector(".rail");
  if (rail) {
    var links = Array.prototype.slice.call(rail.querySelectorAll("a[href^='#']"));
    var targets = links
      .map(function (link) {
        return document.getElementById(link.getAttribute("href").slice(1));
      })
      .filter(Boolean);
    var spy = function () {
      var at = window.scrollY + 120;
      var current = targets[0];
      targets.forEach(function (target) {
        if (target.offsetTop <= at) current = target;
      });
      links.forEach(function (link) {
        link.classList.toggle(
          "on",
          current && link.getAttribute("href") === "#" + current.id
        );
      });
    };
    window.addEventListener("scroll", spy, { passive: true });
    spy();
  }

  // ---------------------------------------------------------------- stream
  var body = document.querySelector("[data-stream]");
  if (body && !reduce) {
    var lines = [
      ["info", "gateway::http", "GET /mirror", [["path", '"/mirror"'], ["took_ms", "18"]]],
      ["debug", "mirror::sync", "scanned 412 files", [["root", '"/srv/mirror"']]],
      ["warn", "mirror::sync", "slow upstream", [["took_ms", "1200"]]],
      ["info", "gateway::health", "probe", [["n", "17"]]],
      ["error", "mirror::sync", "disk 91% full", [["free_gb", "1.5"]]],
      ["debug", "gateway::pool", "acquired", [["conn", "c-31"]]],
      ["info", "gateway::http", "PUT /mirror/debian", [["bytes", "1048576"]]],
      ["trace", "mirror::sync", "hashing", [["part", '"/debian/Packages"']]],
      ["warn", "gateway::pool", "queue deep", [["waiting", "42"]]],
      ["info", "mirror::sync", "ok", [["mirrored", "debian"], ["took_ms", "842"]]],
      ["error", "gateway::http", "upstream refused", [["peer", '"10.0.0.1:873"']]],
      ["fatal", "gateway::boot", "no route", [["iface", '"eth0"']]],
    ];

    var time = 22 * 3600 + 13 * 60 + 24;
    var existing = body.children.length;
    var shown = existing > 0 ? existing : 9;
    var at = existing;
    var seq = 40 + existing;

    function stamp() {
      var h = Math.floor(time / 3600) % 24;
      var m = Math.floor(time / 60) % 60;
      var s = time % 60;
      time += 1;
      return (
        String(h).padStart(2, "0") +
        ":" +
        String(m).padStart(2, "0") +
        ":" +
        String(s).padStart(2, "0")
      );
    }

    function build(record) {
      var line = document.createElement("div");
      line.className = "line";
      var fields = record[3]
        .map(function (pair) {
          return (
            '<span class="k">' + pair[0] + '</span><span class="punct">=</span>' +
            '<span class="v">' + escapeHtml(pair[1]) + "</span>"
          );
        })
        .join(" ");
      line.innerHTML =
        '<span class="no">' + String(seq).padStart(3, "0") + "</span>" +
        '<span class="chip ' + record[0] + '">' + record[0].toUpperCase() + "</span>" +
        '<span class="body"><span class="t">' + stamp() + '</span> ' +
        '<span class="tgt">' + record[1] + "</span> " +
        '<span class="msg">' + escapeHtml(record[2]) + "</span> " +
        fields + "</span>";
      seq += 1;
      return line;
    }

    function escapeHtml(text) {
      return String(text)
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;");
    }

    if (existing === 0) {
      for (var i = 0; i < shown; i++) {
        var node = build(lines[at % lines.length]);
        at += 1;
        node.classList.add("enter");
        node.style.animationDelay = i * 90 + "ms";
        body.appendChild(node);
      }
    }
    Array.prototype.forEach.call(body.children, function (child) {
      child.classList.remove("enter");
      child.style.animation = "none";
    });

    var timer = window.setInterval(function () {
      if (document.hidden) return;
      var next = build(lines[at % lines.length]);
      at += 1;
      var old = body.firstElementChild;
      if (old) old.remove();
      next.classList.add("enter");
      body.appendChild(next);
      Array.prototype.forEach.call(body.children, function (child, index) {
        child.querySelector(".no").textContent = String(seq - shown + index).padStart(3, "0");
        child.classList.remove("enter");
        child.style.animation = "none";
      });
    }, 2600);

    window.addEventListener("pagehide", function () {
      clearInterval(timer);
    });
  }
})();
