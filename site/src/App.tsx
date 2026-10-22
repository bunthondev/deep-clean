import { useEffect, useState } from 'react'

const REPO = 'bunthondev/deep-clean'
const RELEASES = `https://github.com/${REPO}/releases/latest`
const BREW = 'brew install --cask --no-quarantine bunthondev/tap/deepclean'

type Tier = 'safe' | 'review' | 'personal'

const ledger: { name: string; group: string; gb: number; tier: Tier }[] = [
  { name: 'Ollama models', group: 'AI and agent tools', gb: 15.25, tier: 'review' },
  { name: 'Xcode DerivedData', group: 'Dev tool caches', gb: 13.31, tier: 'safe' },
  { name: 'iOS Simulators', group: 'Dev tool caches', gb: 10.52, tier: 'review' },
  { name: 'Large files in Downloads', group: 'Your files', gb: 8.48, tier: 'personal' },
  { name: 'Hugging Face cache', group: 'AI and agent tools', gb: 6.76, tier: 'review' },
  { name: 'api-server/target', group: 'Rust build output', gb: 4.94, tier: 'safe' },
  { name: 'pnpm store', group: 'Package manager caches', gb: 3.44, tier: 'safe' },
  { name: 'shop-web/node_modules', group: 'JavaScript dependencies', gb: 1.93, tier: 'safe' },
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

function DownloadButton({ release, large }: { release: Release | null | undefined; large?: boolean }) {
  const href = release?.zip ?? RELEASES
  const mb = release?.size ? (release.size / 1_048_576).toFixed(1) : null
  return (
    <div className={`download${large ? ' download-large' : ''}`}>
      <div className="download-row">
        <a className="button button-primary" href={href}>
          <AppleMark />
          {release ? `Download for Mac, ${release.version}` : 'Download for Mac'}
        </a>
        <a className="button button-ghost" href={`https://github.com/${REPO}`}>
          View source
        </a>
      </div>
      <p className="download-meta">
        {release === undefined && 'Checking the latest release'}
        {release === null && 'Free and open source. macOS 14 or newer, Apple silicon.'}
        {release && `Free and open source. ${mb ? `${mb} MB zip. ` : ''}macOS 14 or newer, Apple silicon.`}
      </p>
      {large && (
        <p className="download-brew">
          or with Homebrew: <code>{BREW}</code>
        </p>
      )}
    </div>
  )
}

function AppleMark() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" aria-hidden="true" fill="currentColor">
      <path d="M16.37 12.77c-.03-2.6 2.12-3.85 2.22-3.91-1.21-1.77-3.09-2.01-3.76-2.04-1.6-.16-3.12.94-3.93.94-.81 0-2.06-.92-3.39-.9-1.74.03-3.35 1.02-4.25 2.58-1.81 3.14-.46 7.79 1.3 10.34.86 1.25 1.89 2.65 3.24 2.6 1.3-.05 1.79-.84 3.36-.84s2.01.84 3.39.81c1.4-.02 2.29-1.27 3.14-2.52.99-1.45 1.4-2.85 1.42-2.92-.03-.01-2.72-1.04-2.74-4.14zM13.78 5.13c.72-.87 1.2-2.08 1.07-3.29-1.03.04-2.29.69-3.03 1.56-.66.77-1.25 2-1.09 3.18 1.15.09 2.33-.58 3.05-1.45z" />
    </svg>
  )
}

function Icon({ name }: { name: 'scan' | 'explain' | 'trash' | 'shield' | 'eye' | 'lock' }) {
  const paths: Record<typeof name, string> = {
    scan: 'M11 4a7 7 0 1 0 4.95 11.95L20 20l-1.4 1.4-4.06-4.05A7 7 0 0 0 11 4zm0 2a5 5 0 1 1 0 10 5 5 0 0 1 0-10z',
    explain: 'M4 5h16v11H8l-4 4V5zm2 2v8.17L7.17 14H18V7H6zm2 2h8v1.5H8V9zm0 3h5v1.5H8V12z',
    trash: 'M9 3h6l1 2h4v2H4V5h4l1-2zm-3 6h12l-1 12H7L6 9zm3 2v8h1.5v-8H9zm4.5 0v8H15v-8h-1.5z',
    shield: 'M12 2l8 3v6c0 5.25-3.4 9.74-8 11-4.6-1.26-8-5.75-8-11V5l8-3zm0 2.18L6 6.4V11c0 4.1 2.55 7.73 6 8.9 3.45-1.17 6-4.8 6-8.9V6.4l-6-2.22zM10.6 14.6l-2.8-2.8 1.4-1.4 1.4 1.4 4.2-4.2 1.4 1.4-5.6 5.6z',
    eye: 'M12 5c5 0 9 4.5 10 7-1 2.5-5 7-10 7S3 14.5 2 12c1-2.5 5-7 10-7zm0 2C8.3 7 5.2 10 4.2 12c1 2 4.1 5 7.8 5s6.8-3 7.8-5c-1-2-4.1-5-7.8-5zm0 2a3 3 0 1 1 0 6 3 3 0 0 1 0-6z',
    lock: 'M12 2a5 5 0 0 1 5 5v3h2v12H5V10h2V7a5 5 0 0 1 5-5zm0 2a3 3 0 0 0-3 3v3h6V7a3 3 0 0 0-3-3zM7 12v8h10v-8H7zm4 2h2v4h-2v-4z',
  }
  return (
    <span className="icon" aria-hidden="true">
      <svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor">
        <path d={paths[name]} />
      </svg>
    </span>
  )
}

function Ledger() {
  return (
    <div className="ledger" aria-label="Example scan result">
      <div className="ledger-head">
        <span>Found on a typical developer Mac</span>
        <strong>{ledgerTotal.toFixed(2)} GB</strong>
      </div>
      <ol>
        {ledger.map((row) => (
          <li key={row.name} className={`row tier-${row.tier}`}>
            <span className="mark" title={tierLabel[row.tier]} />
            <span className="row-name">
              {row.name}
              <small>{row.group}</small>
            </span>
            <span className="row-size">{row.gb.toFixed(2)} GB</span>
          </li>
        ))}
      </ol>
    </div>
  )
}

export default function App() {
  const release = useLatestRelease()
  return (
    <>
      <header className="top">
        <div className="wrap top-inner">
          <a className="brand" href="#">
            <img src="icon.png" alt="" width="30" height="30" />
            DeepClean
          </a>
          <nav>
            <a href="#how">How it works</a>
            <a href="#finds">What it finds</a>
            <a href="#safety">Safety</a>
            <a href="#install">Install</a>
          </nav>
          <a className="button button-small" href={release?.zip ?? RELEASES}>
            Download
          </a>
        </div>
      </header>

      <main>
        <section className="hero">
          <div className="wrap hero-inner">
            <h1>Reclaim the disk space your tools quietly took.</h1>
            <p className="lede">
              DeepClean is a small native Mac app for developers. It finds package caches, build folders, simulator
              images and leftover app data, explains what each one is, and moves to the Trash only what you confirm.
            </p>
            <DownloadButton release={release} large />
          </div>
          <div className="wrap shot-wrap">
            <img
              className="shot"
              src="screenshot-light.png"
              alt="DeepClean window showing the junk list grouped by safety and a detail pane explaining Xcode DerivedData"
            />
          </div>
        </section>

        <section id="how" className="how">
          <div className="wrap">
            <h2>Three steps, one confirmation</h2>
            <p className="section-lede">
              The scan is read-only. Nothing changes until the final step, and even then it goes to the Trash.
            </p>
            <ol className="steps">
              <li>
                <Icon name="scan" />
                <h3>Scan</h3>
                <p>
                  DeepClean checks the places developer tools hide their caches and walks your project folders for
                  build output. A full pass over a 500 GB disk takes about half a minute.
                </p>
              </li>
              <li>
                <Icon name="explain" />
                <h3>Understand</h3>
                <p>
                  Every item gets a plain description, a safety tier, and a note on what comes back after deleting.
                  Open any folder to see the ten largest things inside it.
                </p>
              </li>
              <li>
                <Icon name="trash" />
                <h3>Trash what you choose</h3>
                <p>
                  Select one row or a whole group, confirm once, and it moves to the Trash. Changed your mind? Put it
                  back from the Trash like any other file.
                </p>
              </li>
            </ol>
          </div>
        </section>

        <section id="finds" className="finds">
          <div className="wrap finds-inner">
            <div className="finds-copy">
              <h2>It knows what developer junk looks like</h2>
              <p className="section-lede">
                Generic cleaners stop at browser caches. DeepClean ships with a catalog of the folders that actually
                fill a developer's disk, each with its own explanation and safety tier.
              </p>
              <ul className="finds-list">
                <li>
                  <strong>Package manager caches</strong>
                  npm, pnpm, Yarn, Bun, pip, uv, Cargo, Go, Gradle, CocoaPods, Homebrew
                </li>
                <li>
                  <strong>Dev tool caches</strong>
                  Xcode DerivedData, iOS simulators, Android images, Playwright and Puppeteer browsers, JetBrains
                  indexes
                </li>
                <li>
                  <strong>Build output in your projects</strong>
                  <code>node_modules</code>, <code>target</code>, <code>.next</code>, <code>dist</code>,{' '}
                  <code>build</code>, <code>.venv</code>, <code>Pods</code>, only next to a matching manifest
                </li>
                <li>
                  <strong>AI and model caches</strong>
                  Ollama, Hugging Face, Torch, Claude Code, Codex, Cursor
                </li>
                <li>
                  <strong>Downloads and leftovers</strong>
                  Installers, archives, files over 200 MB, and data left behind by removed apps
                </li>
              </ul>
            </div>
            <Ledger />
          </div>
        </section>

        <section id="safety" className="safety">
          <div className="wrap">
            <h2>Built to be trusted with your disk</h2>
            <div className="safety-grid">
              <div>
                <Icon name="shield" />
                <h3>Three safety tiers</h3>
                <p>
                  Green items regrow on their own. Amber items are junk only if you stopped using the tool. Blue items
                  are your personal data, listed for awareness with the Trash button disabled.
                </p>
              </div>
              <div>
                <Icon name="eye" />
                <h3>Nothing is hidden</h3>
                <p>
                  Each row shows its full path, size, file count and last change. Reveal in Finder is one click away
                  if you want to look before you decide.
                </p>
              </div>
              <div>
                <Icon name="lock" />
                <h3>No account, no telemetry</h3>
                <p>
                  The app runs entirely on your Mac. Its only network request is a daily check for a newer version on
                  GitHub, and the source is open for anyone to read.
                </p>
              </div>
            </div>
          </div>
        </section>

        <section id="more" className="more">
          <div className="wrap">
            <h2>Also in the sidebar</h2>
            <div className="more-grid">
              <div>
                <h3>Applications</h3>
                <p>
                  Every installed app with its size, source and last-used date. Select one to see its leftovers in
                  Library and uninstall both together.
                </p>
              </div>
              <div>
                <h3>Processes</h3>
                <p>
                  Running processes grouped by app with CPU and memory, so Chrome is one row instead of thirty. Quit
                  or force quit from the list.
                </p>
              </div>
              <div>
                <h3>System</h3>
                <p>
                  Storage, CPU load, memory pressure and battery health, refreshed every two seconds without any
                  helper process.
                </p>
              </div>
            </div>
          </div>
        </section>

        <section id="install" className="install">
          <div className="wrap install-inner">
            <div>
              <h2>Install in a minute</h2>
              <h3 className="install-option">With Homebrew</h3>
              <pre className="brew">
                <code>{BREW}</code>
              </pre>
              <p className="install-note">
                One command, and <code>brew upgrade --cask deepclean</code> keeps it current. The
                <code>--no-quarantine</code> flag skips the Gatekeeper step below.
              </p>
              <h3 className="install-option">Or download it yourself</h3>
              <ol className="install-steps">
                <li>
                  <span>Download the zip and drag DeepClean into Applications.</span>
                </li>
                <li>
                  <span>
                    The build is not notarized by Apple, so macOS blocks the first launch. Clear the flag once in
                    Terminal, or open the app and choose Open Anyway under Privacy &amp; Security.
                  </span>
                  <pre>
                    <code>xattr -d com.apple.quarantine /Applications/DeepClean.app</code>
                  </pre>
                </li>
                <li>
                  <span>
                    Grant Full Disk Access when asked so Mail, Safari and Messages caches can be read. Everything else
                    works without it.
                  </span>
                </li>
              </ol>
            </div>
            <div className="install-cta">
              <img src="icon.png" alt="" width="72" height="72" />
              <h3>DeepClean for Mac</h3>
              <p>Swift and SwiftUI, no dependencies, under 3 MB. Updates come through Homebrew or from inside the app.</p>
              <DownloadButton release={release} />
            </div>
          </div>
        </section>
      </main>

      <footer>
        <div className="wrap footer-inner">
          <span>DeepClean is open source under the MIT license.</span>
          <nav>
            <a href={`https://github.com/${REPO}`}>GitHub</a>
            <a href={RELEASES}>Releases</a>
            <a href={`https://github.com/${REPO}/issues`}>Report a problem</a>
          </nav>
        </div>
      </footer>
    </>
  )
}
