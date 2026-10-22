import { useEffect, useRef, useState } from 'react'

const REPO = 'bunthondev/deep-clean'
const RELEASES = `https://github.com/${REPO}/releases/latest`

type Tier = 'safe' | 'review' | 'personal'

const ledger: { name: string; group: string; gb: number; tier: Tier }[] = [
  { name: 'Ollama models', group: 'AI and agent tools', gb: 15.25, tier: 'review' },
  { name: 'Xcode DerivedData', group: 'Dev tool caches', gb: 13.31, tier: 'safe' },
  { name: 'iOS Simulators', group: 'Dev tool caches', gb: 10.52, tier: 'review' },
  { name: 'Large files in Downloads', group: 'Your files', gb: 8.48, tier: 'personal' },
  { name: 'Hugging Face cache', group: 'AI and agent tools', gb: 6.76, tier: 'review' },
  { name: 'api-server/target', group: 'Rust build output', gb: 4.94, tier: 'safe' },
  { name: 'pnpm store', group: 'Package manager caches', gb: 3.44, tier: 'safe' },
  { name: 'Cargo registry', group: 'Package manager caches', gb: 3.11, tier: 'safe' },
  { name: 'shop-web/node_modules', group: 'JavaScript dependencies', gb: 1.93, tier: 'safe' },
  { name: 'Chrome cache', group: 'Browser caches', gb: 1.57, tier: 'safe' },
]
const ledgerTotal = ledger.reduce((s, i) => s + i.gb, 0)

const tierLabel: Record<Tier, string> = {
  safe: 'Safe to delete',
  review: 'Review first',
  personal: 'Personal data',
}

type Release = { version: string; zip?: string; size?: number }

function useLatestRelease(): Release | null | undefined {
  const [release, setRelease] = useState<Release | null | undefined>(undefined)
  useEffect(() => {
    const ctrl = new AbortController()
    fetch(`https://api.github.com/repos/${REPO}/releases/latest`, {
      headers: { Accept: 'application/vnd.github+json' },
      signal: ctrl.signal,
    })
      .then((r) => (r.ok ? r.json() : Promise.reject(r.status)))
      .then((j) => {
        const asset = (j.assets as { name: string; browser_download_url: string; size: number }[]).find((a) =>
          a.name.endsWith('.zip'),
        )
        setRelease({
          version: String(j.tag_name).replace(/^v/, ''),
          zip: asset?.browser_download_url,
          size: asset?.size,
        })
      })
      .catch(() => setRelease(null))
    return () => ctrl.abort()
  }, [])
  return release
}

function useCountUp(target: number, duration = 1400) {
  const [value, setValue] = useState(0)
  useEffect(() => {
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
      setValue(target)
      return
    }
    let frame = 0
    const start = performance.now()
    const tick = (now: number) => {
      const t = Math.min(1, (now - start) / duration)
      const eased = 1 - Math.pow(1 - t, 3)
      setValue(target * eased)
      if (t < 1) frame = requestAnimationFrame(tick)
    }
    frame = requestAnimationFrame(tick)
    return () => cancelAnimationFrame(frame)
  }, [target, duration])
  return value
}

function DownloadButton({ release }: { release: Release | null | undefined }) {
  const href = release?.zip ?? RELEASES
  const mb = release?.size ? (release.size / 1_048_576).toFixed(1) : null
  return (
    <div className="download">
      <a className="button" href={href}>
        {release ? `Download DeepClean ${release.version}` : 'Download DeepClean'}
      </a>
      <p className="download-meta">
        {release === undefined && 'Checking the latest release'}
        {release === null && 'Free, open source. macOS 14 or newer, Apple silicon.'}
        {release && `Free, open source. ${mb ? `${mb} MB zip, ` : ''}macOS 14 or newer, Apple silicon.`}
      </p>
    </div>
  )
}

function Ledger() {
  const total = useCountUp(ledgerTotal)
  const [shown, setShown] = useState(0)
  const ref = useRef<HTMLOListElement>(null)
  useEffect(() => {
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
      setShown(ledger.length)
      return
    }
    let i = 0
    const id = setInterval(() => {
      i += 1
      setShown(i)
      if (i >= ledger.length) clearInterval(id)
    }, 110)
    return () => clearInterval(id)
  }, [])
  return (
    <div className="ledger" aria-label="Example scan result">
      <div className="ledger-head">
        <span>Found on a typical developer Mac</span>
        <strong>{total.toFixed(2)} GB</strong>
      </div>
      <ol ref={ref}>
        {ledger.map((row, i) => (
          <li key={row.name} className={`row tier-${row.tier}${i < shown ? ' is-in' : ''}`}>
            <span className="mark" title={tierLabel[row.tier]} />
            <span className="row-name">
              {row.name}
              <small>{row.group}</small>
            </span>
            <span className="row-size">{row.gb.toFixed(2)} GB</span>
          </li>
        ))}
      </ol>
      <ul className="legend">
        <li className="tier-safe"><span className="mark" />Safe to delete, comes back on its own</li>
        <li className="tier-review"><span className="mark" />Review first, junk only if you stopped using it</li>
        <li className="tier-personal"><span className="mark" />Personal data, listed but never trashed</li>
      </ul>
    </div>
  )
}

export default function App() {
  const release = useLatestRelease()
  return (
    <>
      <header className="top">
        <a className="brand" href="#">
          <img src="icon.png" alt="" width="28" height="28" />
          DeepClean
        </a>
        <nav>
          <a href="#finds">What it finds</a>
          <a href="#safety">Safety</a>
          <a href="#install">Install</a>
          <a href={`https://github.com/${REPO}`}>Source</a>
        </nav>
      </header>

      <main>
        <section className="hero">
          <div className="hero-copy">
            <h1>Your Mac is full of things you can safely delete.</h1>
            <p className="lede">
              DeepClean finds the caches, build folders and leftover app data that quietly fill a developer's disk.
              It tells you what each one is and what happens if it goes, then moves to the Trash only what you confirm.
            </p>
            <DownloadButton release={release} />
          </div>
          <Ledger />
        </section>

        <figure className="shot">
          <picture>
            <source media="(prefers-color-scheme: dark)" srcSet="screenshot-dark.png" />
            <img src="screenshot-light.png" alt="DeepClean window with the junk list grouped by safety and a detail pane explaining Xcode DerivedData" />
          </picture>
          <figcaption>Every row has a plain explanation, a safety tier, and the ten largest things inside it.</figcaption>
        </figure>

        <section id="finds" className="finds">
          <h2>What it finds</h2>
          <div className="finds-grid">
            <div>
              <h3>Caches that regrow</h3>
              <p>npm, pnpm, Yarn, Bun, pip, uv, Cargo, Go, Gradle, CocoaPods, Homebrew downloads, Playwright and Puppeteer browsers, Xcode DerivedData, JetBrains indexes, browser caches.</p>
            </div>
            <div>
              <h3>Build output inside your projects</h3>
              <p>Walks your project folders and lists every <code>node_modules</code>, <code>target</code>, <code>.next</code>, <code>dist</code>, <code>build</code>, <code>.venv</code> and <code>Pods</code>. Generic names only count when a matching manifest sits next to them, so your real folders are left alone.</p>
            </div>
            <div>
              <h3>Big things worth a second look</h3>
              <p>Ollama and Hugging Face models, iOS simulators, Android emulator images, Docker data, installers and archives sitting in Downloads, files over 200 MB, and app leftovers from software you removed.</p>
            </div>
            <div>
              <h3>Apps, processes and the machine itself</h3>
              <p>Uninstall an app together with its leftovers in Library. See every running process grouped by app with CPU and memory. Watch storage, CPU, memory pressure and battery health from the sidebar.</p>
            </div>
          </div>
        </section>

        <section id="safety" className="safety">
          <h2>How it stays safe</h2>
          <ul>
            <li>
              <strong>Scanning is read-only.</strong> Nothing changes on disk until you press a Trash button and confirm.
            </li>
            <li>
              <strong>Deleting means moving to the Trash.</strong> If something turns out to matter, put it back.
            </li>
            <li>
              <strong>Personal data is only reported.</strong> Your documents, databases and media show up in the list for awareness, with the Trash button disabled.
            </li>
            <li>
              <strong>Every item is explained.</strong> What it is, what regrows after deleting, and what you would lose for good.
            </li>
            <li>
              <strong>No account, no telemetry.</strong> The only network request is the daily check for a newer version, which you can ignore.
            </li>
          </ul>
        </section>

        <section id="install" className="install">
          <h2>Install</h2>
          <ol>
            <li>
              <span>Download the zip and drag DeepClean into Applications.</span>
            </li>
            <li>
              <span>
                The build is not notarized by Apple, so macOS blocks the first launch. Clear the flag once in Terminal:
              </span>
              <pre><code>xattr -d com.apple.quarantine /Applications/DeepClean.app</code></pre>
              <span className="alt">Or open it once, then choose Open Anyway in System Settings under Privacy &amp; Security.</span>
            </li>
            <li>
              <span>Grant Full Disk Access when asked so Mail, Safari and Messages caches can be read. Everything else works without it.</span>
            </li>
          </ol>
          <DownloadButton release={release} />
        </section>
      </main>

      <footer>
        <p>
          Swift and SwiftUI, no dependencies, under 3 MB. Builds with the Command Line Tools alone.
        </p>
        <p>
          <a href={`https://github.com/${REPO}`}>Source on GitHub</a>
          <a href={RELEASES}>All releases</a>
          <a href={`https://github.com/${REPO}/issues`}>Report a problem</a>
        </p>
      </footer>
    </>
  )
}
