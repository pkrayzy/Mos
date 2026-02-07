"use client";

import { useEffect, useMemo, useRef, useState } from "react";

function clamp(n: number, min: number, max: number) {
  return Math.min(max, Math.max(min, n));
}

function easeOutPow(u: number, power: number) {
  const x = clamp(u, 0, 1);
  return 1 - Math.pow(1 - x, power);
}

type EasingPlaygroundProps = {
  className?: string;
};

export function EasingPlayground({ className = "" }: EasingPlaygroundProps) {
  const [stepPx, setStepPx] = useState(18);
  const [gain, setGain] = useState(1.25);
  const [durationMs, setDurationMs] = useState(420);

  const dotRef = useRef<SVGCircleElement | null>(null);

  const MAX_T = 900;
  const MAX_D = 160;

  const graph = useMemo(() => {
    // Mapping: these knobs influence both scale (distance/time) and curve shape.
    const distance = clamp(stepPx * gain, 8, MAX_D);

    const power = clamp(
      2.1 + (gain - 1) * 2.0 + (stepPx - 18) / 24 * 0.55 - (durationMs - 420) / 520 * 0.45,
      1.6,
      5.8
    );

    return { distance, power };
  }, [stepPx, gain, durationMs]);

  const pathD = useMemo(() => {
    const VW = 520;
    const VH = 260;
    const padL = 52;
    const padR = 18;
    const padT = 18;
    const padB = 42;
    const w = VW - padL - padR;
    const h = VH - padT - padB;

    const mapX = (tMs: number) => padL + (clamp(tMs, 0, MAX_T) / MAX_T) * w;
    const mapY = (dPx: number) => padT + h - (clamp(dPx, 0, MAX_D) / MAX_D) * h;

    const steps = 56;
    let d = "";
    for (let i = 0; i <= steps; i += 1) {
      const u = i / steps;
      const t = u * durationMs;
      const y = graph.distance * easeOutPow(u, graph.power);
      const xPx = mapX(t);
      const yPx = mapY(y);
      d += i === 0 ? `M ${xPx.toFixed(2)} ${yPx.toFixed(2)}` : ` L ${xPx.toFixed(2)} ${yPx.toFixed(2)}`;
    }
    return d;
  }, [durationMs, graph.distance, graph.power]);

  useEffect(() => {
    const reduced = window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches ?? false;
    if (reduced) return;

    const dot = dotRef.current;
    if (!dot) return;

    const VW = 520;
    const VH = 260;
    const padL = 52;
    const padR = 18;
    const padT = 18;
    const padB = 42;
    const w = VW - padL - padR;
    const h = VH - padT - padB;

    const mapX = (tMs: number) => padL + (clamp(tMs, 0, MAX_T) / MAX_T) * w;
    const mapY = (dPx: number) => padT + h - (clamp(dPx, 0, MAX_D) / MAX_D) * h;

    let raf = 0;
    const start = performance.now();
    const hold = 320;
    const fade = 140;

    const tick = (now: number) => {
      const elapsed = now - start;
      const cycle = durationMs + hold;
      const t = elapsed % cycle;

      const u = clamp(t / Math.max(1, durationMs), 0, 1);
      const y = graph.distance * easeOutPow(u, graph.power);
      const xPx = mapX(u * durationMs);
      const yPx = mapY(y);

      let alpha = 1;
      if (t < fade) alpha = t / fade;
      const fadeOutStart = durationMs + hold - fade;
      if (t > fadeOutStart) alpha = 1 - (t - fadeOutStart) / fade;

      dot.setAttribute("cx", xPx.toFixed(2));
      dot.setAttribute("cy", yPx.toFixed(2));
      dot.setAttribute("opacity", clamp(alpha, 0, 1).toFixed(2));

      raf = window.requestAnimationFrame(tick);
    };
    raf = window.requestAnimationFrame(tick);

    return () => window.cancelAnimationFrame(raf);
  }, [durationMs, graph.distance, graph.power]);

  return (
    <div className={className}>
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-5 items-start">
        <div className="lg:col-span-7">
          <div className="rounded-2xl border border-white/10 bg-black/35 overflow-hidden">
            <svg
              viewBox="0 0 520 260"
              className="block w-full h-auto"
              aria-label="Easing curve graph"
            >
              <defs>
                <linearGradient id="easeFill" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="0%" stopColor="rgba(255,255,255,0.18)" />
                  <stop offset="100%" stopColor="rgba(255,255,255,0)" />
                </linearGradient>
              </defs>

              {/* Grid */}
              <g stroke="rgba(255,255,255,0.08)" strokeWidth="1">
                {Array.from({ length: 7 }).map((_, i) => {
                  const x = 52 + (i / 6) * (520 - 52 - 18);
                  return <line key={i} x1={x} y1="18" x2={x} y2={260 - 42} />;
                })}
                {Array.from({ length: 5 }).map((_, i) => {
                  const y = 18 + (i / 4) * (260 - 18 - 42);
                  return <line key={i} x1="52" y1={y} x2={520 - 18} y2={y} />;
                })}
              </g>

              {/* Axis labels */}
              <g fill="rgba(255,255,255,0.42)" fontFamily="var(--font-mono)" fontSize="11">
                <text x="52" y={260 - 18}>
                  0ms
                </text>
                <text x={520 - 18} y={260 - 18} textAnchor="end">
                  900ms
                </text>
                <text x="18" y={260 - 42} textAnchor="start">
                  0px
                </text>
                <text x="18" y="26" textAnchor="start">
                  160px
                </text>
              </g>

              {/* Parameter guides */}
              <g stroke="rgba(255,255,255,0.16)" strokeWidth="1" strokeDasharray="4 6">
                {/* Duration marker */}
                <line
                  x1={52 + (durationMs / MAX_T) * (520 - 52 - 18)}
                  y1="18"
                  x2={52 + (durationMs / MAX_T) * (520 - 52 - 18)}
                  y2={260 - 42}
                />
                {/* Distance marker */}
                <line
                  x1="52"
                  y1={18 + (1 - graph.distance / MAX_D) * (260 - 18 - 42)}
                  x2={520 - 18}
                  y2={18 + (1 - graph.distance / MAX_D) * (260 - 18 - 42)}
                />
              </g>

              {/* Fill under curve */}
              <path
                d={`${pathD} L ${52 + (durationMs / MAX_T) * (520 - 52 - 18)} ${260 - 42} L 52 ${260 - 42} Z`}
                fill="url(#easeFill)"
                opacity="0.8"
              />

              {/* Curve */}
              <path
                key={`${stepPx}-${gain}-${durationMs}`}
                d={pathD}
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
                cx="52"
                cy={260 - 42}
                r="4.2"
                fill="rgba(255,255,255,0.95)"
              />
              <circle
                cx="52"
                cy={260 - 42}
                r="2"
                fill="rgba(255,255,255,0.55)"
                opacity="0.7"
              />
            </svg>
          </div>

          <div className="mt-3 flex flex-wrap items-center gap-2">
            <span className="font-mono text-[11px] tracking-[0.18em] uppercase text-white/45">
              distance
            </span>
            <span className="rounded-full border border-white/10 bg-white/5 px-2.5 py-1 font-mono text-xs text-white/70">
              {Math.round(graph.distance)}px
            </span>
            <span className="text-white/35">•</span>
            <span className="font-mono text-[11px] tracking-[0.18em] uppercase text-white/45">
              duration
            </span>
            <span className="rounded-full border border-white/10 bg-white/5 px-2.5 py-1 font-mono text-xs text-white/70">
              {durationMs}ms
            </span>
            <span className="text-white/35">•</span>
            <span className="font-mono text-[11px] tracking-[0.18em] uppercase text-white/45">
              curve
            </span>
            <span className="rounded-full border border-white/10 bg-white/5 px-2.5 py-1 font-mono text-xs text-white/70">
              ease-out pow {graph.power.toFixed(2)}
            </span>
          </div>
        </div>

        <div className="lg:col-span-5">
          <div className="grid gap-4">
            <div className="rounded-2xl border border-white/10 bg-black/35 p-4">
              <div className="flex items-center justify-between">
                <div className="font-display text-sm tracking-[0.18em] uppercase text-white/70">
                  Step
                </div>
                <div className="font-mono text-xs text-white/55">{stepPx}px</div>
              </div>
              <input
                className="mt-3 w-full range"
                type="range"
                min={6}
                max={42}
                step={1}
                value={stepPx}
                onChange={(e) => setStepPx(Number(e.target.value))}
                aria-label="Step length"
              />
              <div className="mt-2 font-mono text-[11px] text-white/40">
                Wheel delta quantization.
              </div>
            </div>

            <div className="rounded-2xl border border-white/10 bg-black/35 p-4">
              <div className="flex items-center justify-between">
                <div className="font-display text-sm tracking-[0.18em] uppercase text-white/70">
                  Gain
                </div>
                <div className="font-mono text-xs text-white/55">×{gain.toFixed(2)}</div>
              </div>
              <input
                className="mt-3 w-full range"
                type="range"
                min={0.6}
                max={2.8}
                step={0.05}
                value={gain}
                onChange={(e) => setGain(Number(e.target.value))}
                aria-label="Gain"
              />
              <div className="mt-2 font-mono text-[11px] text-white/40">
                Amplifies distance and steepens response.
              </div>
            </div>

            <div className="rounded-2xl border border-white/10 bg-black/35 p-4">
              <div className="flex items-center justify-between">
                <div className="font-display text-sm tracking-[0.18em] uppercase text-white/70">
                  Duration
                </div>
                <div className="font-mono text-xs text-white/55">{durationMs}ms</div>
              </div>
              <input
                className="mt-3 w-full range"
                type="range"
                min={120}
                max={900}
                step={10}
                value={durationMs}
                onChange={(e) => setDurationMs(Number(e.target.value))}
                aria-label="Duration"
              />
              <div className="mt-2 font-mono text-[11px] text-white/40">
                Time constant of smoothing.
              </div>
            </div>
          </div>

          <div className="mt-4 rounded-2xl border border-white/10 bg-white/5 p-4">
            <div className="font-mono text-xs text-white/70">
              Mapping preview
            </div>
            <div className="mt-2 font-mono text-[11px] text-white/45">
              distance = step × gain
            </div>
            <div className="mt-3 grid grid-cols-2 gap-2">
              <div className="rounded-xl border border-white/10 bg-black/30 px-3 py-2">
                <div className="font-mono text-[10px] tracking-[0.18em] uppercase text-white/40">
                  step
                </div>
                <div className="mt-1 font-mono text-xs text-white/70">{stepPx}px</div>
              </div>
              <div className="rounded-xl border border-white/10 bg-black/30 px-3 py-2">
                <div className="font-mono text-[10px] tracking-[0.18em] uppercase text-white/40">
                  gain
                </div>
                <div className="mt-1 font-mono text-xs text-white/70">×{gain.toFixed(2)}</div>
              </div>
              <div className="rounded-xl border border-white/10 bg-black/30 px-3 py-2 col-span-2">
                <div className="font-mono text-[10px] tracking-[0.18em] uppercase text-white/40">
                  output
                </div>
                <div className="mt-1 font-mono text-xs text-white/80">
                  {Math.round(graph.distance)}px over {durationMs}ms
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

