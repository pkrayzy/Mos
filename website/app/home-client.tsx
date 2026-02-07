"use client";

import Image from "next/image";
import { useCallback, useEffect, useMemo, useRef } from "react";
import logo512 from "@/assets/image/logo-512.png";
import { FlowField } from "./components/FlowField/FlowField";
import { Magnetic } from "./components/Magnetic/Magnetic";
import { Reveal } from "./components/Reveal/Reveal";
import { EasingPlayground } from "./components/EasingPlayground/EasingPlayground";
import { CopyButton } from "./components/CopyButton/CopyButton";
import { useGithubRelease } from "./services/github";

const FALLBACK_RELEASE_LINK = "https://github.com/Caldis/Mos/releases/latest";

function pickDownloadUrl(release: unknown): string {
  if (!release || typeof release !== "object") return FALLBACK_RELEASE_LINK;

  const assetsRaw = (release as Record<string, unknown>).assets;
  if (!Array.isArray(assetsRaw) || assetsRaw.length === 0) return FALLBACK_RELEASE_LINK;

  const assets = assetsRaw
    .map((asset) => {
      if (!asset || typeof asset !== "object") return null;
      const record = asset as Record<string, unknown>;
      const name = typeof record.name === "string" ? record.name : null;
      const url =
        typeof record.browser_download_url === "string" ? record.browser_download_url : null;
      if (!name || !url) return null;
      return { name, url };
    })
    .filter(Boolean) as { name: string; url: string }[];

  if (assets.length === 0) return FALLBACK_RELEASE_LINK;

  const byExt = (ext: string) => assets.find((a) => a.name.toLowerCase().endsWith(ext));

  return byExt(".zip")?.url || byExt(".dmg")?.url || assets[0]?.url || FALLBACK_RELEASE_LINK;
}

export default function HomeClient() {
  const { data: release } = useGithubRelease();

  const versionLabel = useMemo(() => {
    const tag = release?.tag_name;
    return typeof tag === "string" && tag.trim() ? `v${tag.replace(/^v/i, "")}` : null;
  }, [release?.tag_name]);

  const downloadUrl = useMemo(() => pickDownloadUrl(release), [release]);

  const homebrewRef = useRef<HTMLDivElement | null>(null);
  const pendingHomebrewFlashRef = useRef(false);
  const homebrewFlashStartTimerRef = useRef<number | null>(null);
  const homebrewFlashTimerRef = useRef<number | null>(null);

  const flashHomebrew = useCallback((delayMs = 0) => {
    const el = homebrewRef.current;
    if (!el) return;

    if (homebrewFlashStartTimerRef.current) {
      window.clearTimeout(homebrewFlashStartTimerRef.current);
      homebrewFlashStartTimerRef.current = null;
    }
    if (homebrewFlashTimerRef.current) {
      window.clearTimeout(homebrewFlashTimerRef.current);
      homebrewFlashTimerRef.current = null;
    }

    const start = () => {
      el.classList.remove("homebrew-highlight");
      // Force reflow so the animation restarts reliably.
      // eslint-disable-next-line @typescript-eslint/no-unused-expressions
      el.offsetWidth;
      el.classList.add("homebrew-highlight");

      homebrewFlashTimerRef.current = window.setTimeout(() => {
        el.classList.remove("homebrew-highlight");
        homebrewFlashTimerRef.current = null;
      }, 1200);
    };

    if (delayMs > 0) {
      homebrewFlashStartTimerRef.current = window.setTimeout(() => {
        homebrewFlashStartTimerRef.current = null;
        start();
      }, delayMs);
    } else {
      start();
    }
  }, []);

  useEffect(() => {
    const el = homebrewRef.current;
    if (!el) return;

    const io = new IntersectionObserver(
      (entries) => {
        const entry = entries[0];
        if (!entry?.isIntersecting) return;
        if (!pendingHomebrewFlashRef.current) return;
        pendingHomebrewFlashRef.current = false;
        flashHomebrew(500);
      },
      { threshold: 0.35 }
    );

    io.observe(el);

    return () => {
      io.disconnect();
      if (homebrewFlashStartTimerRef.current) {
        window.clearTimeout(homebrewFlashStartTimerRef.current);
        homebrewFlashStartTimerRef.current = null;
      }
      if (homebrewFlashTimerRef.current) {
        window.clearTimeout(homebrewFlashTimerRef.current);
        homebrewFlashTimerRef.current = null;
      }
    };
  }, [flashHomebrew]);

  const scrollToHomebrew = () => {
    const el = homebrewRef.current ?? document.getElementById("homebrew");
    if (!el) return;

    const reduced = window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches ?? false;

    const rect = el.getBoundingClientRect();
    const inView = rect.top < window.innerHeight * 0.78 && rect.bottom > window.innerHeight * 0.22;
    if (inView) {
      pendingHomebrewFlashRef.current = false;
      flashHomebrew(500);
    } else {
      pendingHomebrewFlashRef.current = true;
    }

    el.scrollIntoView({ behavior: reduced ? "auto" : "smooth", block: "start" });
  };

  return (
    <div className="min-h-[100svh] text-[color:var(--fg0)]">
      <a
        href="#content"
        className="sr-only focus:not-sr-only focus:fixed focus:z-[100] focus:top-4 focus:left-4 focus:px-4 focus:py-2 focus:rounded-xl focus:bg-black/70 focus:text-white focus:outline-none"
      >
        Skip to content
      </a>

      <div className="fixed inset-0 -z-10 overflow-hidden">
        <FlowField className="absolute inset-0" />
        <div className="orb left-[-140px] top-[-120px] w-[380px] h-[380px] bg-[color:var(--accent)]" />
        <div className="orb right-[-180px] top-[10vh] w-[420px] h-[420px] bg-[color:var(--accent3)] [animation-delay:-1.2s]" />
        <div className="orb left-[12vw] bottom-[-220px] w-[520px] h-[520px] bg-[color:var(--accent2)] [animation-delay:-2.1s]" />
      </div>

      <header className="fixed left-0 right-0 top-0 z-50 px-4 sm:px-6">
        <nav className="mx-auto mt-4 sm:mt-6 max-w-6xl rounded-[var(--radius-xl)] glass ring-accent">
          <div className="flex items-center justify-between px-4 sm:px-5 py-3">
            <div className="flex items-center gap-3">
              <Image
                src={logo512}
                alt="Mos app icon"
                width={52}
                height={52}
                className="object-contain rounded-[18px]"
                priority
              />
              <div className="font-display text-[15px] sm:text-base font-semibold tracking-[0.18em] uppercase text-white/90">
                Mos
              </div>
            </div>

            <div className="hidden sm:flex items-center gap-2">
              <a
                href="https://github.com/Caldis/Mos"
                target="_blank"
                rel="noopener noreferrer"
                className="px-3 py-2 rounded-xl text-white/70 hover:text-white/92 transition-colors"
              >
                GitHub
              </a>
              <Magnetic strength={18}>
                <a
                  href={downloadUrl}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="group relative overflow-hidden rounded-2xl px-4 py-2.5 text-sm font-semibold tracking-wide text-black border border-black/10 shadow-elevated"
                  style={{
                    background:
                      "linear-gradient(180deg, rgba(255,255,255,0.96) 0%, rgba(255,255,255,0.84) 100%)",
                  }}
                >
                  <span className="relative z-10">Download</span>
                  <span className="absolute inset-0 opacity-0 group-hover:opacity-100 transition-opacity duration-500 [background:radial-gradient(600px_220px_at_50%_0%,rgba(0,0,0,0.16),transparent_55%)]" />
                </a>
              </Magnetic>
            </div>

            <div className="flex sm:hidden items-center gap-2">
              <a
                href={downloadUrl}
                target="_blank"
                rel="noopener noreferrer"
                className="rounded-2xl px-3 py-2 text-sm font-semibold text-black border border-black/10 shadow-elevated"
                style={{
                  background:
                    "linear-gradient(180deg, rgba(255,255,255,0.96) 0%, rgba(255,255,255,0.84) 100%)",
                }}
              >
                Get Mos
              </a>
            </div>
          </div>
        </nav>
      </header>

      <main id="content" className="mx-auto max-w-6xl px-4 sm:px-6">
        <section className="relative min-h-[100svh] pt-28 sm:pt-36 pb-10 sm:pb-12 flex flex-col">
          <div className="flex-1 flex items-start sm:items-center">
            <div className="w-full">
            <div
              className="inline-flex items-center gap-3 rounded-full border border-white/10 bg-black/40 px-4 py-2 text-xs text-white/70 shadow-elevated motion-safe:animate-[hero-in_900ms_var(--ease-out)_both]"
              style={{ animationDelay: "40ms" }}
            >
              <span className="inline-flex items-center gap-2">
                <span className="h-2 w-2 rounded-full bg-[color:var(--accent)] shadow-[0_0_22px_rgba(255,255,255,0.35)]" />
                Smooth scrolling for mouse wheels on macOS
              </span>
              <span className="hidden sm:inline text-white/35">•</span>
              <span className="hidden sm:inline font-mono text-white/45">
                per-app profiles · independent axes · buttons & shortcuts
              </span>
            </div>

            <h1
              className="mt-7 font-display text-balance text-[42px] leading-[1.02] sm:text-[72px] md:text-[84px] text-white motion-safe:animate-[hero-in_1000ms_var(--ease-out)_both]"
              style={{ animationDelay: "110ms" }}
            >
              Turn the wheel
              <span className="block">
                into{" "}
                <span
                  className="inline-block text-flow"
                  style={{ textShadow: "0 0 42px rgba(255,255,255,0.08)" }}
                >
                  flow
                </span>
                .
              </span>
            </h1>

            <p
              className="mt-5 max-w-2xl text-balance text-[15px] sm:text-lg text-white/72 leading-relaxed motion-safe:animate-[hero-in_1000ms_var(--ease-out)_both]"
              style={{ animationDelay: "180ms" }}
            >
              Mos is a free macOS utility that makes your mouse scrolling feel trackpad-smooth,
              without taking away control. Shape curves, split axes, and override behavior per
              app.
            </p>

            <div
              className="mt-8 flex flex-col sm:flex-row sm:items-start gap-3 sm:gap-4 motion-safe:animate-[hero-in_1050ms_var(--ease-out)_both]"
              style={{ animationDelay: "250ms" }}
            >
              <div className="flex flex-col items-start w-fit">
                <Magnetic strength={22}>
                  <a
                    href={downloadUrl}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="group relative overflow-hidden rounded-[18px] px-6 py-3.5 text-sm sm:text-base font-semibold tracking-wide text-black shadow-elevated border border-black/10 inline-flex items-center justify-center"
                    style={{
                      background:
                        "linear-gradient(180deg, rgba(255,255,255,0.96) 0%, rgba(255,255,255,0.84) 100%)",
                    }}
                  >
                    <span className="relative z-10">Download Mos</span>
                    <span className="absolute inset-0 opacity-0 group-hover:opacity-100 transition-opacity duration-500 [background:radial-gradient(800px_240px_at_30%_0%,rgba(0,0,0,0.18),transparent_55%)]" />
                  </a>
                </Magnetic>
                <a
                  href="#homebrew"
                  onClick={(e) => {
                    e.preventDefault();
                    scrollToHomebrew();
                  }}
                  className="mt-2 self-center text-xs font-mono text-white/50 hover:text-white/75 transition-colors underline decoration-white/15 hover:decoration-white/35 underline-offset-4"
                >
                  通过 Homebrew 安装
                </a>
              </div>

              <Magnetic strength={14}>
                <a
                  href="https://github.com/Caldis/Mos"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="group inline-flex items-center justify-center rounded-[18px] px-6 py-3.5 text-sm sm:text-base font-semibold tracking-wide text-white/85 border border-white/12 bg-white/5 hover:bg-white/8 transition-colors"
                >
                  <span className="mr-2 opacity-70 group-hover:opacity-100 transition-opacity">
                    ↗
                  </span>
                  <span>View on GitHub</span>
                </a>
              </Magnetic>

              <div className="sm:ml-auto sm:self-center text-xs text-white/45">
                <div className="font-mono">Requires macOS 10.13+</div>
                <div className="font-mono">Free · Open source</div>
              </div>
            </div>
            </div>
          </div>

          <div className="mt-8 sm:mt-10 flex items-center gap-3 text-white/40">
            <div className="h-[1px] flex-1 hairline" />
            <div className="font-mono text-[11px] tracking-[0.18em] uppercase">
              Scroll to explore
            </div>
            <div className="h-[1px] flex-1 hairline" />
          </div>
        </section>

        <section className="py-16 sm:py-24">
          <Reveal>
            <h2 className="font-display text-balance text-3xl sm:text-5xl text-white leading-tight">
              Deterministic scroll. Tunable feel.
            </h2>
          </Reveal>
          <Reveal delayMs={90}>
            <p className="mt-4 max-w-3xl text-white/68 leading-relaxed">
              Mos turns raw wheel deltas into predictable motion. Keep the same feel across apps,
              override it per-app when needed.
            </p>
          </Reveal>

          <div className="mt-10 grid grid-cols-1 md:grid-cols-12 gap-4">
            <Reveal className="md:col-span-12" delayMs={140}>
              <div className="group relative h-full rounded-[var(--radius-xl)] glass shadow-elevated overflow-hidden border border-white/10">
                <div className="absolute inset-0 opacity-0 group-hover:opacity-100 transition-opacity duration-700 [background:radial-gradient(900px_420px_at_20%_0%,rgba(255,255,255,0.10),transparent_55%)]" />
                <div className="relative p-6 sm:p-8">
                  <div className="font-display text-sm tracking-[0.18em] uppercase text-white/70">
                    Curves & Acceleration
                  </div>
                  <div className="mt-4 text-2xl sm:text-3xl text-white font-semibold">
                    Shape the feel.
                  </div>
                  <p className="mt-3 text-white/66 leading-relaxed">
                    Smoothness is a curve. Tune step, gain, and duration and watch how the curve
                    maps raw wheel deltas into controlled motion.
                  </p>
                  <EasingPlayground className="mt-6" />
                </div>
              </div>
            </Reveal>

            <Reveal className="md:col-span-6" delayMs={180}>
              <div className="group relative h-full rounded-[var(--radius-xl)] glass shadow-elevated overflow-hidden border border-white/10">
                <div className="absolute inset-0 opacity-0 group-hover:opacity-100 transition-opacity duration-700 [background:radial-gradient(900px_420px_at_80%_0%,rgba(255,255,255,0.08),transparent_55%)]" />
                <div className="relative p-6 sm:p-8">
                  <div className="font-display text-sm tracking-[0.18em] uppercase text-white/70">
                    Independent Axes
                  </div>
                  <div className="mt-4 text-2xl sm:text-3xl text-white font-semibold">
                    Split X and Y.
                  </div>
                  <p className="mt-3 text-white/66 leading-relaxed">
                    Tune vertical and horizontal scroll separately, including smoothness and
                    reverse, for mice and touchpads.
                  </p>

                  <div className="mt-6 rounded-2xl border border-white/10 bg-black/30 p-5">
                    <div className="flex items-center gap-3">
                      <div className="h-10 w-10 rounded-2xl border border-white/10 bg-white/5 grid place-items-center">
                        <span className="font-mono text-xs text-white/60">Y</span>
                      </div>
                      <div className="flex-1">
                        <div className="h-2 rounded-full bg-white/10 overflow-hidden">
                          <div className="h-full w-[68%] bg-[color:var(--accent)]" />
                        </div>
                        <div className="mt-2 font-mono text-xs text-white/45">
                          Smoothness 68%
                        </div>
                      </div>
                    </div>
                    <div className="mt-4 flex items-center gap-3">
                      <div className="h-10 w-10 rounded-2xl border border-white/10 bg-white/5 grid place-items-center">
                        <span className="font-mono text-xs text-white/60">X</span>
                      </div>
                      <div className="flex-1">
                        <div className="h-2 rounded-full bg-white/10 overflow-hidden">
                          <div className="h-full w-[42%] bg-[color:var(--accent3)]" />
                        </div>
                        <div className="mt-2 font-mono text-xs text-white/45">
                          Smoothness 42%
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </Reveal>

            <Reveal className="md:col-span-6" delayMs={210}>
              <div className="group relative h-full rounded-[var(--radius-xl)] glass shadow-elevated overflow-hidden border border-white/10">
                <div className="absolute inset-0 opacity-0 group-hover:opacity-100 transition-opacity duration-700 [background:radial-gradient(900px_420px_at_40%_0%,rgba(255,255,255,0.09),transparent_55%)]" />
                <div className="relative p-6 sm:p-8">
                  <div className="font-display text-sm tracking-[0.18em] uppercase text-white/70">
                    Per-app Profiles
                  </div>
                  <div className="mt-4 text-2xl sm:text-3xl text-white font-semibold">
                    Different apps, different feel.
                  </div>
                  <p className="mt-3 text-white/66 leading-relaxed">
                    Let each app inherit defaults or override scroll and button rules. Precision
                    where it matters, smooth everywhere else.
                  </p>

                  <div className="mt-6 grid grid-cols-3 gap-2">
                    {[
                      { name: "Xcode", c: "rgba(255,255,255,0.18)" },
                      { name: "Safari", c: "rgba(255,255,255,0.14)" },
                      { name: "Figma", c: "rgba(255,255,255,0.12)" },
                      { name: "Terminal", c: "rgba(255,255,255,0.10)" },
                      { name: "Notion", c: "rgba(255,255,255,0.10)" },
                      { name: "Chrome", c: "rgba(255,255,255,0.10)" },
                    ].map((a) => (
                      <div
                        key={a.name}
                        className="rounded-2xl border border-white/10 bg-white/5 p-3 hover:bg-white/8 transition-colors"
                      >
                        <div
                          className="h-10 w-10 rounded-xl border border-white/10 grid place-items-center"
                          style={{ background: a.c }}
                        >
                          <span className="font-display text-[13px] text-white/90">
                            {a.name.slice(0, 1)}
                          </span>
                        </div>
                        <div className="mt-2 font-mono text-[11px] text-white/55">
                          {a.name}
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              </div>
            </Reveal>

            <Reveal className="md:col-span-12" delayMs={240}>
              <div className="group relative h-full rounded-[var(--radius-xl)] glass shadow-elevated overflow-hidden border border-white/10">
                <div className="absolute inset-0 opacity-0 group-hover:opacity-100 transition-opacity duration-700 [background:radial-gradient(900px_420px_at_60%_0%,rgba(255,255,255,0.07),transparent_55%)]" />
                <div className="relative p-6 sm:p-8">
                  <div className="font-display text-sm tracking-[0.18em] uppercase text-white/70">
                    Buttons & Shortcuts
                  </div>
                  <div className="mt-4 text-2xl sm:text-3xl text-white font-semibold">
                    Bind, record, repeat.
                  </div>
                  <p className="mt-3 text-white/66 leading-relaxed">
                    Record mouse or keyboard events and bind them to system shortcuts. See live
                    monitors to debug what your devices are sending.
                  </p>

                  <div className="mt-6 rounded-2xl border border-white/10 bg-black/30 p-5">
                    <div className="font-mono text-xs text-white/45">Quick Bind</div>
                    <div className="mt-3 grid gap-2">
                      {[
                        { k: "Button 4", v: "Mission Control" },
                        { k: "Button 5", v: "Next Space" },
                        { k: "Wheel Click", v: "App Switcher" },
                      ].map((row) => (
                        <div
                          key={row.k}
                          className="flex items-center justify-between rounded-xl border border-white/10 bg-white/5 px-3 py-2"
                        >
                          <div className="font-mono text-xs text-white/75">{row.k}</div>
                          <div className="font-mono text-xs text-white/45">{row.v}</div>
                        </div>
                      ))}
                    </div>
                  </div>
                </div>
              </div>
            </Reveal>
          </div>
        </section>

        <section className="pt-0 pb-16 sm:pb-24">
          <div className="rounded-[28px] glass shadow-elevated border border-white/10 overflow-hidden">
            <div className="px-6 sm:px-10 py-10 sm:py-14">
              <Reveal>
                <h3 className="font-display text-balance text-3xl sm:text-6xl text-white leading-tight">
                  Download Mos. Feel the difference today.
                </h3>
              </Reveal>
              <Reveal delayMs={90}>
                <p className="mt-4 max-w-3xl text-white/68 leading-relaxed">
                  Install in seconds, tune at your pace, and keep your scroll behavior consistent
                  across the apps you live in.
                </p>
              </Reveal>

              <Reveal delayMs={160}>
                <div className="mt-8 flex flex-col sm:flex-row sm:items-center gap-3">
                  <Magnetic strength={22}>
                    <a
                        href={downloadUrl}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="group relative overflow-hidden rounded-[18px] px-6 py-3.5 text-sm sm:text-base font-semibold tracking-wide text-black shadow-elevated border border-black/10 inline-flex items-center justify-center"
                        style={{
                          background:
                            "linear-gradient(180deg, rgba(255,255,255,0.96) 0%, rgba(255,255,255,0.84) 100%)",
                        }}
                      >
                      <span className="relative z-10">
                        Download
                      </span>
                        <span className="absolute inset-0 opacity-0 group-hover:opacity-100 transition-opacity duration-500 [background:radial-gradient(900px_260px_at_30%_0%,rgba(0,0,0,0.18),transparent_55%)]" />
                      </a>
                  </Magnetic>

                  <Magnetic strength={14}>
                    <a
                      href="https://github.com/Caldis/Mos/releases"
                      target="_blank"
                      rel="noopener noreferrer"
                      className="inline-flex items-center justify-center rounded-[18px] px-6 py-3.5 text-sm sm:text-base font-semibold tracking-wide text-white/85 border border-white/12 bg-white/5 hover:bg-white/8 transition-colors"
                    >
                      Release notes
                    </a>
                  </Magnetic>

                  <Magnetic strength={14}>
                    <a
                      href="https://github.com/Caldis/Mos/wiki"
                      target="_blank"
                      rel="noopener noreferrer"
                      className="inline-flex items-center justify-center rounded-[18px] px-6 py-3.5 text-sm sm:text-base font-semibold tracking-wide text-white/85 border border-white/12 bg-white/5 hover:bg-white/8 transition-colors"
                    >
                      Docs
                    </a>
                  </Magnetic>
                </div>
              </Reveal>

              <Reveal delayMs={220}>
                <div
                  id="homebrew"
                  ref={homebrewRef}
                  className="mt-8 scroll-mt-28 rounded-[22px] border border-white/10 bg-black/35 p-5 sm:p-6"
                >
                  <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
                    <div>
                      <div className="font-display text-sm tracking-[0.18em] uppercase text-white/70">
                        Homebrew
                      </div>
                      <div className="mt-2 font-mono text-sm text-white/75">
                        brew install --cask mos
                      </div>
                    </div>
                    <CopyButton
                      value="brew install --cask mos"
                      className="self-start sm:self-auto rounded-2xl px-4 py-2.5 text-sm font-semibold border border-white/12 bg-white/5 hover:bg-white/8 transition-colors text-white/85"
                    >
                      Copy
                    </CopyButton>
                  </div>
                  <div className="mt-4 font-mono text-xs text-white/45">
                    Tip: If you’re on beta, your cask might be <span className="text-white/70">mos@beta</span>.
                  </div>
                </div>
              </Reveal>
            </div>

            <div className="px-6 sm:px-10 py-6 border-t border-white/10 flex flex-col sm:flex-row sm:items-center justify-between gap-3 text-white/45">
              <div className="font-mono text-xs">
                {versionLabel ? `Latest ${versionLabel}` : "Latest release"} · Requires macOS 10.13+
              </div>
              <div className="flex items-center gap-4 font-mono text-xs">
                <a
                  href="https://github.com/Caldis/Mos"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="hover:text-white/80 transition-colors"
                >
                  GitHub
                </a>
                <a
                  href="https://github.com/Caldis/Mos/wiki"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="hover:text-white/80 transition-colors"
                >
                  Wiki
                </a>
                <a
                  href="https://github.com/Caldis/Mos/releases"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="hover:text-white/80 transition-colors"
                >
                  Releases
                </a>
              </div>
            </div>
          </div>
        </section>
      </main>
    </div>
  );
}
