"use client";

import { useEffect, useMemo, useRef, useState } from "react";

function clamp(n: number, min: number, max: number) {
  return Math.min(max, Math.max(min, n));
}

function roundTo(n: number, decimals: number) {
  const p = Math.pow(10, decimals);
  return Math.round(n * p) / p;
}

// Ported from Mos:
// Mos/Utils/Constants.swift -> OPTIONS_SCROLL_DEFAULT.generateDurationTransition(with:)
function generateDurationTransition(duration: number) {
  // Slider upper bound is 5.0; Mos adds +0.2 so the result never hits 0.
  const upperLimit = 5.0 + 0.2;
  const d = clamp(duration, 0, 5.0);
  const val = 1 - Math.sqrt(d / upperLimit);
  return roundTo(val, 3);
}

// Ported from Mos:
// Mos/ScrollCore/ScrollFilter.swift
function scrollFilterFill(window: number[], nextValue: number) {
  const first = window[1] ?? 0;
  const diff = nextValue - first;
  return [
    first,
    first + 0.23 * diff,
    first + 0.5 * diff,
    first + 0.77 * diff,
    nextValue,
  ];
}

function niceCeil(n: number) {
  const x = Math.max(1e-6, n);
  const p = Math.pow(10, Math.floor(Math.log10(x)));
  const s = x / p;
  let m = 1;
  if (s <= 1) m = 1;
  else if (s <= 2) m = 2;
  else if (s <= 5) m = 5;
  else m = 10;
  return m * p;
}

type EasingPlaygroundProps = {
  className?: string;
};

export function EasingPlayground({ className = "" }: EasingPlaygroundProps) {
  // Match Mos defaults (OPTIONS_SCROLL_DEFAULT)
  const [step, setStep] = useState(33.6);
  const [gain, setGain] = useState(2.7);
  const [duration, setDuration] = useState(4.35);

  const dotRef = useRef<SVGCircleElement | null>(null);

  const sim = useMemo(() => {
    // A compact simulation of Mos' ScrollPoster + Interpolator.lerp + ScrollFilter.
    // We visualize the posted vertical deltas (deadZone-clamped) over time.
    const manualContinuationThreshold = 0.18; // ScrollPoster.manualContinuationThreshold
    const deadZone = 1.0; // OPTIONS_SCROLL_DEFAULT.deadZone
    const burstTicks = 10; // A short "wheel burst" to resemble the in-app monitor.
    const maxFrames = 90;
    const fps = 60;
    const dt = 1 / fps;

    const trans = generateDurationTransition(duration);

    let current = 0;
    let buffer = 0;
    let deltaPrev = 0;

    let t = 0;
    let lastManualTime = 0;
    let manualInputEnded = true;
    let trackingEndInserted = false;
    let settled = 0;

    let filterWindow = [0.0, 0.0];
    const samples: number[] = [];

    for (let frame = 0; frame < maxFrames; frame += 1) {
      if (frame < burstTicks) {
        const y = step;
        if (y * deltaPrev > 0) {
          buffer += y * gain;
        } else {
          buffer = y * gain;
          current = 0;
        }
        deltaPrev = y;
        lastManualTime = t;
        manualInputEnded = false;
        trackingEndInserted = false;
      }

      // Interpolator.lerp(src: current, dest: buffer, trans: durationTransition)
      const delta = (buffer - current) * trans;
      current += delta;

      // ScrollFilter.fill(with:)
      filterWindow = scrollFilterFill(filterWindow, delta);
      const filtered = filterWindow[0] ?? 0;
      const out = Math.abs(filtered) > deadZone ? filtered : 0;

      // Simulate the "TrackingEnd" marker frame Mos emits after manual input stops.
      if (
        !manualInputEnded &&
        !trackingEndInserted &&
        t - lastManualTime > manualContinuationThreshold
      ) {
        manualInputEnded = true;
        trackingEndInserted = true;
        samples.push(0);
      }

      samples.push(out);

      const residual = buffer - current;
      const residualMagnitude = Math.abs(residual);
      if (manualInputEnded && residualMagnitude <= deadZone && Math.abs(out) <= deadZone) {
        settled += 1;
        if (settled >= 6) break;
      } else {
        settled = 0;
      }

      t += dt;
    }

    const maxAbs = Math.max(1, ...samples.map((v) => Math.abs(v)));
    const yMax = niceCeil(maxAbs * 1.06);
    return { samples, trans, yMax };
  }, [duration, gain, step]);

  const graph = useMemo(() => {
    const VW = 860;
    const VH = 280;
    const padL = 56;
    const padR = 18;
    const padT = 18;
    const padB = 44;
    const w = VW - padL - padR;
    const h = VH - padT - padB;

    const samples = sim.samples;
    const N = Math.max(2, samples.length);
    const mapX = (i: number) => padL + (clamp(i, 0, N - 1) / (N - 1)) * w;
    const mapY = (v: number) => {
      const y = clamp(v, 0, sim.yMax);
      return padT + h - (y / sim.yMax) * h;
    };

    const points = samples.map((v, i) => ({
      x: mapX(i),
      y: mapY(v),
    }));

    let d = "";
    for (let i = 0; i < points.length; i += 1) {
      const p = points[i]!;
      d += i === 0 ? `M ${p.x.toFixed(2)} ${p.y.toFixed(2)}` : ` L ${p.x.toFixed(2)} ${p.y.toFixed(2)}`;
    }

    const baselineY = mapY(0);
    const fill = `${d} L ${mapX(points.length - 1).toFixed(2)} ${baselineY.toFixed(2)} L ${mapX(0).toFixed(2)} ${baselineY.toFixed(2)} Z`;

    return { VW, VH, padL, padR, padT, padB, points, d, fill, baselineY };
  }, [sim.samples, sim.yMax]);

  useEffect(() => {
    const reduced = window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches ?? false;
    if (reduced) return;

    const dot = dotRef.current;
    if (!dot) return;

    let raf = 0;
    const start = performance.now();
    const travel = 1260;
    const hold = 320;
    const fade = 140;

    const tick = (now: number) => {
      const elapsed = now - start;
      const cycle = travel + hold;
      const t = elapsed % cycle;

      const pts = graph.points;
      const u = clamp(t / Math.max(1, travel), 0, 1);
      const pos = u * (pts.length - 1);
      const i0 = Math.floor(pos);
      const i1 = Math.min(pts.length - 1, i0 + 1);
      const k = clamp(pos - i0, 0, 1);
      const p0 = pts[i0] ?? pts[0]!;
      const p1 = pts[i1] ?? pts[pts.length - 1]!;
      const xPx = p0.x + (p1.x - p0.x) * k;
      const yPx = p0.y + (p1.y - p0.y) * k;

      let alpha = 1;
      if (t < fade) alpha = t / fade;
      const fadeOutStart = travel + hold - fade;
      if (t > fadeOutStart) alpha = 1 - (t - fadeOutStart) / fade;

      dot.setAttribute("cx", xPx.toFixed(2));
      dot.setAttribute("cy", yPx.toFixed(2));
      dot.setAttribute("opacity", clamp(alpha, 0, 1).toFixed(2));

      raf = window.requestAnimationFrame(tick);
    };
    raf = window.requestAnimationFrame(tick);

    return () => window.cancelAnimationFrame(raf);
  }, [graph.points]);

  return (
    <div className={className}>
      <div className="rounded-2xl border border-white/10 bg-black/35 overflow-hidden">
        <svg
          viewBox={`0 0 ${graph.VW} ${graph.VH}`}
          className="block w-full h-auto"
          aria-label="Scroll curve graph"
        >
          <defs>
            <linearGradient id="easeFill" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="rgba(255,255,255,0.14)" />
              <stop offset="100%" stopColor="rgba(255,255,255,0)" />
            </linearGradient>
          </defs>

          {/* Grid */}
          <g stroke="rgba(255,255,255,0.08)" strokeWidth="1">
            {Array.from({ length: 7 }).map((_, i) => {
              const x =
                graph.padL + (i / 6) * (graph.VW - graph.padL - graph.padR);
              return (
                <line
                  key={i}
                  x1={x}
                  y1={graph.padT}
                  x2={x}
                  y2={graph.VH - graph.padB}
                />
              );
            })}
            {Array.from({ length: 5 }).map((_, i) => {
              const y =
                graph.padT + (i / 4) * (graph.VH - graph.padT - graph.padB);
              return (
                <line
                  key={i}
                  x1={graph.padL}
                  y1={y}
                  x2={graph.VW - graph.padR}
                  y2={y}
                />
              );
            })}
          </g>

          {/* Fill under curve */}
          <path d={graph.fill} fill="url(#easeFill)" opacity="0.9" />

          {/* Curve */}
          <path
            key={`${step}-${gain}-${duration}`}
            d={graph.d}
            fill="none"
            stroke="rgba(255,255,255,0.92)"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
            pathLength={1}
            strokeDasharray={1}
            strokeDashoffset={1}
            style={{
              animation: "stroke-in 900ms var(--ease-out) both",
            }}
          />

          {/* Animated dot */}
          <circle
            ref={dotRef}
            cx={graph.padL}
            cy={graph.baselineY}
            r="4.2"
            fill="rgba(255,255,255,0.95)"
          />
          <circle
            cx={graph.padL}
            cy={graph.baselineY}
            r="2"
            fill="rgba(255,255,255,0.55)"
            opacity="0.7"
          />
        </svg>
      </div>

      <div className="mt-4 grid gap-4 md:grid-cols-3">
        <div className="rounded-2xl border border-white/10 bg-black/35 p-4">
          <div className="flex items-center justify-between">
            <div className="font-display text-sm tracking-[0.18em] uppercase text-white/70">
              Step
            </div>
            <div className="font-mono text-xs text-white/55">
              {step.toFixed(1)}
            </div>
          </div>
          <input
            className="mt-3 w-full range"
            type="range"
            min={6}
            max={72}
            step={0.1}
            value={step}
            onChange={(e) => setStep(Number(e.target.value))}
            aria-label="Step"
          />
          <div className="mt-2 font-mono text-[11px] text-white/40">
            Quantization floor for wheel deltas.
          </div>
        </div>

        <div className="rounded-2xl border border-white/10 bg-black/35 p-4">
          <div className="flex items-center justify-between">
            <div className="font-display text-sm tracking-[0.18em] uppercase text-white/70">
              Gain
            </div>
            <div className="font-mono text-xs text-white/55">
              ×{gain.toFixed(2)}
            </div>
          </div>
          <input
            className="mt-3 w-full range"
            type="range"
            min={0.6}
            max={5.4}
            step={0.05}
            value={gain}
            onChange={(e) => setGain(Number(e.target.value))}
            aria-label="Gain"
          />
          <div className="mt-2 font-mono text-[11px] text-white/40">
            Scales distance per tick and how fast the curve ramps.
          </div>
        </div>

        <div className="rounded-2xl border border-white/10 bg-black/35 p-4">
          <div className="flex items-center justify-between">
            <div className="font-display text-sm tracking-[0.18em] uppercase text-white/70">
              Duration
            </div>
            <div className="font-mono text-xs text-white/55">
              {duration.toFixed(2)}
            </div>
          </div>
          <input
            className="mt-3 w-full range"
            type="range"
            min={0.2}
            max={5}
            step={0.05}
            value={duration}
            onChange={(e) => setDuration(Number(e.target.value))}
            aria-label="Duration"
          />
          <div className="mt-2 font-mono text-[11px] text-white/40">
            Smoothing time constant (higher means longer tail).
          </div>
        </div>
      </div>

      <div className="mt-3 font-mono text-[11px] tracking-[0.18em] uppercase text-white/40">
        ScrollCore curve
      </div>
    </div>
  );
}
