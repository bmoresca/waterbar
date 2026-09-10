#!/usr/bin/env python3
"""Generate site/index.html.

The milestone list and the model constants are imported from the real engine,
so the marketing page can't drift from what the app actually does.
"""

import html
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "plugin", "engine"))

import water  # noqa: E402

REPO = os.environ.get("WATERBAR_REPO", "bmoresca/waterbar")
TAP = os.environ.get("WATERBAR_TAP", "bmoresca/tap")
COFFEE = water.DEFAULT_CONFIG and "https://donate.stripe.com/9B6dR24TMbHReeTf0x9IQ0d"
VERSION = "1.0.0"


def milestone_cards():
    out = []
    for threshold, icon, name, blurb in water.MILESTONES:
        out.append(
            '<li class="ach"><span class="ach-i">{icon}</span>'
            '<span class="ach-n">{name}</span>'
            '<span class="ach-v">{amount}</span>'
            '<span class="ach-b">{blurb}</span></li>'.format(
                icon=icon,
                name=html.escape(name),
                amount=html.escape(water.format_ml(threshold)),
                blurb=html.escape(blurb),
            )
        )
    return "\n".join(out)


def verb_samples():
    """The same verbs the spinner actually uses."""
    return [t.format(amount="{amount}") for t in water.VERB_TEMPLATES[:8]]


TEMPLATE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>WaterBar &mdash; how much water is Claude Code drinking?</title>
<meta name="description" content="A macOS menu bar app that estimates the water your Claude Code sessions consume, and replaces the thinking spinner with a live readout. Free, open source, no account.">
<meta property="og:title" content="WaterBar">
<meta property="og:description" content="Your thinking spinner, now with a water bill.">
<meta property="og:image" content="https://watercount.betomoresca.com/waterbar.png">
<meta property="og:url" content="https://watercount.betomoresca.com">
<meta name="twitter:card" content="summary_large_image">
<link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>&#128167;</text></svg>">
<style>
  :root {{
    --blue:   #1289db;
    --deep:   #0b3f6b;
    --ink:    #10202c;
    --muted:  #5b7385;
    --line:   #dae6ef;
    --bg:     #ffffff;
    --wash:   #f2f8fc;
    --coffee: #98682f;
    --radius: 14px;
  }}
  * {{ box-sizing: border-box; }}
  html {{ scroll-behavior: smooth; }}
  body {{
    margin: 0;
    overflow-x: hidden;
    background: var(--bg);
    color: var(--ink);
    font: 16px/1.6 ui-sans-serif, -apple-system, BlinkMacSystemFont, "Segoe UI", Inter, system-ui, sans-serif;
    -webkit-font-smoothing: antialiased;
  }}
  .wrap {{ width: 100%; max-width: 1020px; margin: 0 auto; padding: 0 22px; }}
  a {{ color: var(--blue); }}
  h1, h2, h3 {{ line-height: 1.15; letter-spacing: -0.021em; margin: 0; }}
  h2 {{ font-size: clamp(26px, 4vw, 36px); }}
  .eyebrow {{
    font-size: 11px; font-weight: 700; letter-spacing: .13em; text-transform: uppercase;
    color: var(--blue); margin-bottom: 12px;
  }}
  section {{ padding: 78px 0; border-top: 1px solid var(--line); }}
  .lede {{ color: var(--muted); font-size: 17px; max-width: 60ch; margin: 14px 0 0; }}

  /* ---------- nav ---------- */
  nav {{
    display: flex; align-items: center; justify-content: space-between;
    gap: 16px; padding: 18px 0; font-size: 14px;
  }}
  .brand {{ display: flex; align-items: center; gap: 9px; font-weight: 650; color: #fff; text-decoration: none; }}
  .brand span {{ font-size: 20px; }}
  nav {{ flex-wrap: wrap; }}
  nav .links {{ display: flex; gap: 22px; align-items: center; flex-wrap: wrap; }}
  nav .links a {{ color: rgba(255,255,255,.82); text-decoration: none; }}
  nav .links a:hover {{ color: #fff; }}

  /* ---------- hero ---------- */
  .hero {{
    background: radial-gradient(1100px 520px at 18% -8%, #1f9ae8 0%, #0d5d9c 46%, #08263f 100%);
    color: #fff; border-top: 0; padding-bottom: 90px;
  }}
  .hero h1 {{ font-size: clamp(34px, 6vw, 58px); margin-top: 26px; max-width: 15ch; }}
  .hero p.sub {{ color: rgba(255,255,255,.80); font-size: 18px; max-width: 54ch; margin: 20px 0 0; }}
  .hero-grid {{ display: grid; grid-template-columns: 1.05fr .95fr; gap: 46px; align-items: center; margin-top: 40px; }}
  @media (max-width: 860px) {{ .hero-grid {{ grid-template-columns: 1fr; gap: 34px; }} }}

  /* ---------- terminal ---------- */
  .term {{
    background: #06121d; border: 1px solid rgba(255,255,255,.13); border-radius: var(--radius);
    padding: 17px 19px; font: 13.5px/1.75 ui-monospace, SFMono-Regular, "SF Mono", Menlo, monospace;
    box-shadow: 0 24px 60px rgba(0,0,0,.36); overflow: hidden;
  }}
  .term .dots {{ display: flex; gap: 6px; margin-bottom: 13px; }}
  .term .dots i {{ width: 10px; height: 10px; border-radius: 50%; background: #2b4155; }}
  .term .dots i:first-child {{ background: #e05c53; }}
  .term .dots i:nth-child(2) {{ background: #e0b44c; }}
  .term .dots i:nth-child(3) {{ background: #4cae5a; }}
  .term .row {{ color: #9fb6c8; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }}
  .term .you {{ color: #6f8ba1; }}
  .term .spin {{ color: #6cc6ff; }}
  .term .meta {{ color: #55708a; }}
  .term .strike {{ color: #55708a; text-decoration: line-through; opacity: .6; }}
  .caret {{ display: inline-block; width: 8px; background: #6cc6ff; animation: blink 1.05s step-end infinite; }}
  @keyframes blink {{ 50% {{ opacity: 0; }} }}

  /* ---------- buttons ---------- */
  .cta {{ display: flex; flex-wrap: wrap; gap: 12px; margin-top: 30px; align-items: center; }}
  .btn {{
    display: inline-flex; align-items: center; gap: 9px; text-decoration: none;
    padding: 12px 20px; border-radius: 10px; font-weight: 600; font-size: 15px;
    border: 1px solid transparent; transition: transform .12s ease, box-shadow .12s ease;
  }}
  .btn:hover {{ transform: translateY(-1px); }}
  .btn-primary {{ background: #fff; color: var(--deep); box-shadow: 0 8px 24px rgba(0,0,0,.22); }}
  .btn-ghost {{ border-color: rgba(255,255,255,.34); color: #fff; }}
  .btn-dark {{ background: var(--deep); color: #fff; }}
  .note {{ font-size: 13px; color: rgba(255,255,255,.62); margin-top: 16px; }}

  /* ---------- copy box ---------- */
  .copy {{
    display: flex; align-items: stretch; gap: 0; margin-top: 26px;
    border: 1px solid rgba(255,255,255,.22); border-radius: 10px; overflow: hidden;
    background: rgba(255,255,255,.07); max-width: 460px; min-width: 0;
  }}
  .copy code {{
    flex: 1; min-width: 0; padding: 13px 15px; color: #dceefc;
    font: 13.5px/1.4 ui-monospace, SFMono-Regular, Menlo, monospace;
    overflow-x: auto; white-space: nowrap; display: flex; align-items: center;
  }}
  .copy button {{
    border: 0; border-left: 1px solid rgba(255,255,255,.22); background: rgba(255,255,255,.10);
    color: #fff; padding: 0 17px; cursor: pointer; font-size: 13px; font-weight: 600; font-family: inherit;
  }}
  .copy button:hover {{ background: rgba(255,255,255,.19); }}
  .copy.light {{ border-color: var(--line); background: var(--wash); }}
  .copy.light code {{ color: var(--ink); }}
  .copy.light button {{ background: #fff; color: var(--deep); border-left-color: var(--line); }}

  /* ---------- shot ---------- */
  .shot {{ display: flex; justify-content: center; }}
  .shot .frame {{
    width: 340px; max-width: 100%; max-height: 560px; overflow: hidden;
    border-radius: 16px; border: 1px solid rgba(255,255,255,.16);
    box-shadow: 0 30px 70px rgba(2,22,40,.44);
    /* The popover is much taller than the hero copy beside it. Cap the height
       and let the tail fade rather than leaving a column of dead space. */
    -webkit-mask-image: linear-gradient(#000 78%, transparent 100%);
    mask-image: linear-gradient(#000 78%, transparent 100%);
  }}
  .shot img {{ display: block; width: 100%; }}
  @media (max-width: 860px) {{
    .shot .frame {{ max-height: 420px; }}
  }}

  /* ---------- features ---------- */
  .feats {{ display: grid; grid-template-columns: repeat(3, 1fr); gap: 20px; margin-top: 42px; }}
  @media (max-width: 860px) {{ .feats {{ grid-template-columns: 1fr; }} }}
  .feat {{ background: var(--wash); border: 1px solid var(--line); border-radius: var(--radius); padding: 22px; }}
  .feat h3 {{ font-size: 16px; margin-bottom: 8px; }}
  .feat p {{ margin: 0; color: var(--muted); font-size: 14.5px; }}
  .feat .ic {{ font-size: 22px; display: block; margin-bottom: 12px; }}

  /* ---------- achievements ---------- */
  .achs {{
    list-style: none; padding: 0; margin: 40px 0 0;
    display: grid; grid-template-columns: repeat(auto-fill, minmax(224px, 1fr));
    grid-auto-rows: 1fr; gap: 10px;
  }}
  .ach {{
    display: grid; grid-template-columns: auto 1fr auto; grid-template-rows: auto auto;
    gap: 2px 11px; align-items: center;
    border: 1px solid var(--line); border-radius: 11px; padding: 12px 14px; background: #fff;
  }}
  .ach-i {{ grid-row: span 2; font-size: 21px; }}
  .ach-n {{ font-weight: 620; font-size: 14px; }}
  .ach-v {{ justify-self: end; }}
  .ach-v {{ font-size: 11.5px; color: var(--blue); font-weight: 650; font-variant-numeric: tabular-nums; }}
  .ach-b {{ grid-column: 2 / span 2; font-size: 12px; color: var(--muted); line-height: 1.45; }}

  /* ---------- table ---------- */
  table {{ width: 100%; border-collapse: collapse; margin-top: 26px; font-size: 14.5px; }}
  th, td {{ text-align: left; padding: 11px 12px; border-bottom: 1px solid var(--line); }}
  th {{ font-size: 11px; text-transform: uppercase; letter-spacing: .09em; color: var(--muted); }}
  td:nth-child(2) {{ font-variant-numeric: tabular-nums; white-space: nowrap; }}
  .scroller {{ overflow-x: auto; }}

  /* ---------- callout ---------- */
  .callout {{
    border-left: 3px solid var(--blue); background: var(--wash);
    padding: 20px 24px; border-radius: 0 var(--radius) var(--radius) 0; margin-top: 30px;
  }}
  .callout p {{ margin: 0; color: var(--muted); font-size: 15px; }}
  .callout p + p {{ margin-top: 12px; }}
  .callout strong {{ color: var(--ink); }}

  /* ---------- steps ---------- */
  .steps {{ counter-reset: s; margin-top: 36px; display: grid; gap: 18px; }}
  .step {{ display: grid; grid-template-columns: 34px minmax(0, 1fr); gap: 16px; align-items: start; }}
  .step > div {{ min-width: 0; }}
  .step::before {{
    counter-increment: s; content: counter(s);
    width: 34px; height: 34px; border-radius: 50%; background: var(--deep); color: #fff;
    display: grid; place-items: center; font-size: 14px; font-weight: 700;
  }}
  .step h3 {{ font-size: 16px; margin-bottom: 5px; }}
  .step p {{ margin: 0; color: var(--muted); font-size: 14.5px; }}

  /* ---------- footer ---------- */
  footer {{ background: #08263f; color: rgba(255,255,255,.66); padding: 52px 0 40px; font-size: 14px; }}
  footer a {{ color: #9fd4f7; }}
  .fgrid {{ display: flex; flex-wrap: wrap; gap: 30px; justify-content: space-between; align-items: flex-start; }}
  .coffee {{
    display: inline-flex; align-items: center; gap: 9px; text-decoration: none;
    background: rgba(255,255,255,.09); border: 1px solid rgba(255,255,255,.2);
    color: #f3d9b8 !important; padding: 11px 18px; border-radius: 10px; font-weight: 600;
  }}
  .coffee:hover {{ background: rgba(255,255,255,.15); }}
  .fine {{ margin-top: 34px; font-size: 12.5px; color: rgba(255,255,255,.44); max-width: 70ch; }}
  /* ---------- phones (last: media queries add no specificity) ---------- */
  @media (max-width: 560px) {{
    .wrap {{ padding: 0 18px; }}
    section {{ padding: 52px 0; }}
    nav {{ padding: 14px 0; gap: 10px; }}
    /* Anchors to sections further down the page aren't worth a wrapped,
       cramped second row on a phone; the GitHub link is. */
    nav .links a:not(:last-child) {{ display: none; }}
    .hero {{ padding-bottom: 56px; }}
    .hero h1 {{ margin-top: 18px; }}
    .hero p.sub {{ font-size: 16px; }}
    .term {{ padding: 14px; font-size: 11.5px; }}
    .term .meta {{ display: none; }}
    .cta .btn {{ flex: 1 1 auto; justify-content: center; }}
    .achs {{ grid-template-columns: 1fr; }}
    .feat {{ padding: 18px; }}
    .shot .frame {{ max-height: 380px; }}
    .fgrid {{ gap: 22px; }}
    /* On a phone the command matters more than the single-line look: wrap it
       so the whole thing is readable without a sideways scroll nobody
       discovers. */
    .copy {{ align-items: center; }}
    /* display:flex on the desktop rule makes the text one unwrappable flex
       item, so it has to go back to block for the wrap to take. */
    .copy code {{ display: block; white-space: pre-wrap; overflow-wrap: anywhere; }}
    .copy button {{ align-self: stretch; }}
  }}
</style>
</head>
<body>

<div class="hero">
  <div class="wrap">
    <nav>
      <a class="brand" href="/"><span>&#128167;</span> WaterBar</a>
      <div class="links">
        <a href="#features">Features</a>
        <a href="#achievements">Achievements</a>
        <a href="#numbers">The numbers</a>
        <a href="https://github.com/{repo}">GitHub</a>
      </div>
    </nav>

    <div class="hero-grid">
      <div>
        <h1>Your thinking spinner, now with a water bill.</h1>
        <p class="sub">
          Claude Code says <em>Pondering&hellip;</em> while it works. WaterBar replaces that
          with an estimate of the water the request is drinking &mdash; and keeps a
          running total in your menu bar, with milestones to unlock.
        </p>

        <div class="term" aria-hidden="true">
          <div class="dots"><i></i><i></i><i></i></div>
          <div class="row"><span class="you">&gt;</span> refactor the auth middleware</div>
          <div class="row"><span class="strike">Pondering&hellip;</span></div>
          <div class="row"><span class="spin" id="verb">Boiling off 27 mL</span><span class="caret">&nbsp;</span>
            <span class="meta"> (12s &middot; esc to interrupt)</span></div>
        </div>

        <div class="cta">
          <a class="btn btn-primary" href="#install">Install</a>
          <a class="btn btn-ghost" href="https://github.com/{repo}/releases/latest/download/WaterBar.dmg">Download .dmg</a>
        </div>
        <p class="note">Free and open source &middot; macOS 13+ &middot; Apple silicon &amp; Intel &middot; No account, no network</p>
      </div>

      <div class="shot"><div class="frame"><img src="waterbar.png" alt="The WaterBar menu bar popover, showing 627 litres across 22,544 requests, progress toward the Cubic Metre milestone, a 14-day chart and the achievement list." width="380"></div></div>
    </div>
  </div>
</div>

<section id="features">
  <div class="wrap">
    <p class="eyebrow">What it does</p>
    <h2>A running tally of something nobody was counting.</h2>
    <p class="lede">Every Claude Code request has a token count. WaterBar turns that into
    millilitres, adds it up, and puts the number where you'll actually see it.</p>

    <div class="feats">
      <div class="feat"><span class="ic">&#9203;</span>
        <h3>Live in the spinner</h3>
        <p>The thinking verb becomes <em>Evaporating 22&nbsp;mL</em>. It updates after every
        request, using what the last one actually cost.</p></div>
      <div class="feat"><span class="ic">&#127894;</span>
        <h3>{n_milestones} milestones</h3>
        <p>From your first millilitre to an Olympic swimming pool. Each one arrives as a
        notification, whether or not you wanted to know.</p></div>
      <div class="feat"><span class="ic">&#128200;</span>
        <h3>Today, this week, all time</h3>
        <p>A 14-day chart, your thirstiest projects, and a breakdown by model &mdash; Opus
        costs a great deal more than Haiku.</p></div>
      <div class="feat"><span class="ic">&#128274;</span>
        <h3>No account. No network.</h3>
        <p>It reads the transcripts Claude Code already writes to your disk. The app links
        no networking frameworks at all &mdash; it cannot phone anywhere.</p></div>
      <div class="feat"><span class="ic">&#129518;</span>
        <h3>Every constant is yours</h3>
        <p>The whole model lives in one editable JSON file. Think the numbers are wrong?
        Change them and rebuild the totals.</p></div>
      <div class="feat"><span class="ic">&#128230;</span>
        <h3>Counts your whole history</h3>
        <p>First launch prices every session you've ever run. And the ledger is
        append-only, so old totals survive Claude Code's transcript cleanup.</p></div>
    </div>
  </div>
</section>

<section id="install">
  <div class="wrap">
    <p class="eyebrow">Install</p>
    <h2>Two ways in.</h2>

    <div class="steps">
      <div class="step">
        <div>
          <h3>Homebrew &mdash; recommended</h3>
          <p>Clears the quarantine flag for you, so there's no Gatekeeper detour at all.</p>
          <div class="copy light">
            <code id="brew">brew install --cask {tap}/waterbar</code>
            <button onclick="copyText('brew', this)">Copy</button>
          </div>
        </div>
      </div>
      <div class="step">
        <div>
          <h3>Or download the disk image</h3>
          <p>Drag WaterBar to Applications. Because the app is ad-hoc signed rather than
          notarized, macOS blocks it the first time.</p>
          <p style="margin-top:10px">On <strong>macOS&nbsp;15 Sequoia and later</strong>, open
          <strong>System&nbsp;Settings &rarr; Privacy&nbsp;&amp;&nbsp;Security</strong>, scroll to
          Security, and click <strong>Open&nbsp;Anyway</strong>. Apple removed the old
          Control-click shortcut in Sequoia. On macOS&nbsp;13&ndash;14, Control-click the app
          &rarr; <strong>Open</strong> &rarr; <strong>Open</strong>. Once, not every launch.</p>
          <p style="margin-top:14px">
            <a class="btn btn-dark" href="https://github.com/{repo}/releases/latest/download/WaterBar.dmg">Download WaterBar {version}</a>
          </p>
        </div>
      </div>
      <div class="step">
        <div>
          <h3>Optional: the Claude Code plugin</h3>
          <p>WaterBar refreshes the spinner on its own every 20 seconds. The plugin does it
          the instant a request lands, and adds <code>/water</code> for a full report.</p>
          <div class="copy light">
            <code id="plug">/plugin marketplace add https://github.com/{repo}</code>
            <button onclick="copyText('plug', this)">Copy</button>
          </div>
        </div>
      </div>
    </div>
  </div>
</section>

<section id="achievements">
  <div class="wrap">
    <p class="eyebrow">Achievements</p>
    <h2>{n_milestones} milestones, in ascending order of concern.</h2>
    <p class="lede">Cumulative, across every project. They unlock quietly and arrive as a
    notification.</p>
    <ul class="achs">
{milestones}
    </ul>
  </div>
</section>

<section id="numbers">
  <div class="wrap">
    <p class="eyebrow">The numbers</p>
    <h2>These are estimates. Loudly.</h2>
    <p class="lede">
      Anthropic doesn't publish per-request water use, and if it did the figure would move
      with the datacenter, the season and the grid. Nothing here is measured. What WaterBar
      does is apply a transparent chain of published constants to a token count:
    </p>

    <div class="callout">
      <p><strong>tokens &rarr; watt-hours &rarr; kWh (&times; PUE) &rarr; litres (&times; on-site cooling + grid water)</strong></p>
    </div>

    <div class="scroller">
    <table>
      <tr><th>Constant</th><th>Default</th><th>Where it comes from</th></tr>
      <tr><td>Opus, output tokens</td><td>3.00 Wh / 1k</td><td>Scaled from the anchors below</td></tr>
      <tr><td>Sonnet, output tokens</td><td>1.10 Wh / 1k</td><td>&nbsp;&Prime;</td></tr>
      <tr><td>Haiku, output tokens</td><td>0.30 Wh / 1k</td><td>&nbsp;&Prime;</td></tr>
      <tr><td>Input tokens</td><td>~1/30th of output</td><td>Prefill is one parallel pass; each output token is its own forward pass</td></tr>
      <tr><td>Cache reads</td><td>~1/200th of output</td><td>The KV state already exists; it only has to move</td></tr>
      <tr><td>Datacenter PUE</td><td>1.10</td><td>Typical hyperscale overhead</td></tr>
      <tr><td>On-site cooling</td><td>1.80 L / kWh</td><td>US datacenter water use efficiency</td></tr>
      <tr><td>Grid electricity</td><td>3.10 L / kWh</td><td>Water spent generating the power itself</td></tr>
    </table>
    </div>

    <div class="callout">
      <p>Those defaults were fitted between two public anchors. <strong>Google (2025)</strong>
      put the median Gemini text prompt at roughly 0.24&nbsp;Wh and 0.26&nbsp;mL &mdash; a small,
      heavily optimised model on a short prompt. <strong>Li et&nbsp;al. (2023)</strong>, &ldquo;Making
      AI Less Thirsty&rdquo;, put GPT-3-scale inference nearer 500&nbsp;mL per 10&ndash;50 responses.</p>
      <p>A heavy agentic Opus turn lands around <strong>20&ndash;30&nbsp;mL</strong>. If you think
      that's wrong, it probably is &mdash; every constant is in
      <code>~/.claude/water/model.json</code>, and <code>WaterBar rebuild</code> re-totals from them.</p>
    </div>
  </div>
</section>

<footer>
  <div class="wrap">
    <div class="fgrid">
      <div>
        <div style="color:#fff;font-weight:650;font-size:16px;margin-bottom:8px">&#128167; WaterBar</div>
        <div><a href="https://github.com/{repo}">Source on GitHub</a> &middot;
             <a href="https://github.com/{repo}/releases">Releases</a> &middot;
             <a href="https://github.com/{repo}/blob/main/README.md">Docs</a></div>
      </div>
      <div>
        <a class="coffee" href="{coffee}">&#9749; Buy me a coffee</a>
        <div style="font-size:12px;margin-top:9px;opacity:.6">A cup takes about 140 litres to grow.</div>
      </div>
    </div>
    <p class="fine">
      WaterBar is not affiliated with, endorsed by, or connected to Anthropic. &ldquo;Claude&rdquo;
      and &ldquo;Claude Code&rdquo; are trademarks of Anthropic. Every water figure this app
      displays is an estimate derived from token counts using public research; none of it is
      measured, and it should not be cited as a factual measurement of anyone's water use.
    </p>
  </div>
</footer>

<script>
  // The same verbs the app ships with.
  var VERBS = {verbs};
  var el = document.getElementById('verb');
  var i = 0;
  function jitter() {{ return (18 + Math.random() * 16).toFixed(0) + ' mL'; }}
  setInterval(function () {{
    i = (i + 1) % VERBS.length;
    el.style.opacity = 0;
    setTimeout(function () {{
      el.textContent = VERBS[i].replace('{{amount}}', jitter());
      el.style.opacity = 1;
    }}, 170);
  }}, 2100);
  el.style.transition = 'opacity .17s ease';

  function copyText(id, btn) {{
    navigator.clipboard.writeText(document.getElementById(id).textContent.trim()).then(function () {{
      var was = btn.textContent;
      btn.textContent = 'Copied';
      setTimeout(function () {{ btn.textContent = was; }}, 1400);
    }});
  }}
</script>
</body>
</html>
"""


def main():
    import json as _json
    page = TEMPLATE.format(
        repo=REPO,
        tap=TAP,
        coffee=COFFEE,
        version=VERSION,
        n_milestones=len(water.MILESTONES),
        milestones=milestone_cards(),
        verbs=_json.dumps(verb_samples()),
    )
    out = os.path.join(HERE, "index.html")
    with open(out, "w", encoding="utf-8") as fh:
        fh.write(page)
    print("wrote %s (%.1f KB)" % (out, len(page) / 1024))


if __name__ == "__main__":
    main()
