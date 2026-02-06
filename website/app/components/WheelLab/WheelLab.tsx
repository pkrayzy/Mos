"use client";

import { useEffect, useRef } from "react";

function clamp(n: number, min: number, max: number) {
  return Math.min(max, Math.max(min, n));
}

export function WheelLab() {
  const rootRef = useRef<HTMLDivElement | null>(null);
  const rawDotRef = useRef<HTMLDivElement | null>(null);
  const mosDotRef = useRef<HTMLDivElement | null>(null);
  const rawValRef = useRef<HTMLSpanElement | null>(null);
  const mosValRef = useRef<HTMLSpanElement | null>(null);
  const rafRef = useRef<number | null>(null);
  const rangePxRef = useRef(140);

  useEffect(() => {
    const root = rootRef.current;
    const rawDot = rawDotRef.current;
    const mosDot = mosDotRef.current;
    const rawVal = rawValRef.current;
    const mosVal = mosValRef.current;
    if (!root || !rawDot || !mosDot || !rawVal || !mosVal) return;

    const reduced = window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches ?? false;

    let raw = 0;
    let target = 0;
    let mos = 0;
    let v = 0;

    const updateRange = () => {
      const rect = root.getBoundingClientRect();
      // Keep some breathing room for glow + labels.
      rangePxRef.current = clamp(rect.height - 110, 90, 220);
    };
    updateRange();

    const apply = () => {
      const range = rangePxRef.current;
      const rawY = raw * (range / 2);
      const mosY = mos * (range / 2);

      rawDot.style.transform = `translate3d(-50%, -50%, 0) translate3d(0, ${rawY}px, 0)`;
      mosDot.style.transform = `translate3d(-50%, -50%, 0) translate3d(0, ${mosY}px, 0)`;

      rawVal.textContent = `${Math.round(((raw + 1) / 2) * 100)}%`;
      mosVal.textContent = `${Math.round(((mos + 1) / 2) * 100)}%`;
    };

    const onWheel = (event: WheelEvent) => {
      // If the user is clearly “scrolling the page”, we still want the lab to respond.
      const delta = (event.deltaY || event.deltaX) * 0.0022;
      raw = clamp(raw + delta, -1, 1);
      target = raw;
      apply();
    };

    let dragging = false;
    let dragStartY = 0;
    let dragStartVal = 0;

    const onPointerDown = (event: PointerEvent) => {
      dragging = true;
      root.setPointerCapture?.(event.pointerId);
      dragStartY = event.clientY;
      dragStartVal = raw;
    };
    const onPointerMove = (event: PointerEvent) => {
      if (!dragging) return;
      const range = rangePxRef.current;
      const dy = event.clientY - dragStartY;
      raw = clamp(dragStartVal + dy / (range / 2), -1, 1);
      target = raw;
      apply();
    };
    const onPointerUp = () => {
      dragging = false;
    };

    root.addEventListener("wheel", onWheel, { passive: true });
    root.addEventListener("pointerdown", onPointerDown, { passive: true });
    root.addEventListener("pointermove", onPointerMove, { passive: true });
    root.addEventListener("pointerup", onPointerUp, { passive: true });
    root.addEventListener("pointercancel", onPointerUp, { passive: true });
    window.addEventListener("resize", updateRange, { passive: true });

    const tick = () => {
      if (!reduced) {
        const k = 0.065;
        const damping = 0.82;
        v = (v + (target - mos) * k) * damping;
        mos = clamp(mos + v, -1, 1);
      } else {
        mos = target;
      }

      apply();
      rafRef.current = window.requestAnimationFrame(tick);
    };

    rafRef.current = window.requestAnimationFrame(tick);

    return () => {
      if (rafRef.current) window.cancelAnimationFrame(rafRef.current);
      root.removeEventListener("wheel", onWheel);
      root.removeEventListener("pointerdown", onPointerDown);
      root.removeEventListener("pointermove", onPointerMove);
      root.removeEventListener("pointerup", onPointerUp);
      root.removeEventListener("pointercancel", onPointerUp);
      window.removeEventListener("resize", updateRange);
    };
  }, []);

  return (
    <div className="p-5 sm:p-7">
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-5 sm:gap-6 items-stretch">
        <div className="lg:col-span-5">
          <div className="font-display text-white/85 text-xl sm:text-2xl leading-tight">
            Raw input vs Mos smoothing.
          </div>
          <p className="mt-3 text-white/62 leading-relaxed">
            The <span className="text-white/80">RAW</span> marker jumps to wheel deltas. The{" "}
            <span className="text-white/80">MOS</span> marker eases into motion like a trackpad.
          </p>

          <div className="mt-5 grid gap-2">
            <div className="flex items-center justify-between rounded-2xl border border-white/10 bg-black/35 px-4 py-3">
              <div className="flex items-center gap-2">
                <span className="h-2 w-2 rounded-full bg-white/45" />
                <span className="font-mono text-xs text-white/70">RAW</span>
              </div>
              <span ref={rawValRef} className="font-mono text-xs text-white/55">
                50%
              </span>
            </div>
            <div className="flex items-center justify-between rounded-2xl border border-white/10 bg-black/35 px-4 py-3">
              <div className="flex items-center gap-2">
                <span className="h-2 w-2 rounded-full bg-[color:var(--accent)] shadow-[0_0_20px_rgba(183,255,78,0.55)]" />
                <span className="font-mono text-xs text-white/70">MOS</span>
              </div>
              <span ref={mosValRef} className="font-mono text-xs text-white/55">
                50%
              </span>
            </div>
          </div>

          <div className="mt-5 font-mono text-[11px] text-white/40">
            Tip: scroll over the lab, or drag inside the panel on touch devices.
          </div>
        </div>

        <div className="lg:col-span-7">
          <div
            ref={rootRef}
            className="relative h-56 sm:h-64 rounded-[22px] border border-white/10 bg-black/35 overflow-hidden touch-none"
            style={{
              backgroundImage:
                "radial-gradient(800px 280px at 50% 0%, rgba(255,255,255,0.08), transparent 60%), linear-gradient(180deg, rgba(255,255,255,0.05), rgba(0,0,0,0))",
            }}
          >
            <div className="absolute inset-0 opacity-[0.28] pointer-events-none">
              <div className="absolute inset-0 [background:linear-gradient(transparent,rgba(255,255,255,0.08),transparent)] opacity-40" />
              <div className="absolute inset-0 [background:repeating-linear-gradient(90deg,rgba(255,255,255,0.06)_0px,rgba(255,255,255,0.06)_1px,transparent_1px,transparent_18px)]" />
              <div className="absolute inset-0 [background:repeating-linear-gradient(0deg,rgba(255,255,255,0.05)_0px,rgba(255,255,255,0.05)_1px,transparent_1px,transparent_18px)]" />
            </div>

            <div className="absolute left-1/2 top-1/2 h-[70%] w-px bg-white/10 -translate-x-1/2 -translate-y-1/2" />

            <div className="absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2 font-mono text-[11px] text-white/35 tracking-[0.18em] uppercase">
              Center
            </div>

            {/* RAW */}
            <div
              ref={rawDotRef}
              className="absolute left-1/2 top-1/2 h-4 w-4 -translate-x-1/2 -translate-y-1/2 rounded-full border border-white/18 bg-white/8 shadow-[0_10px_30px_rgba(0,0,0,0.55)]"
            />

            {/* MOS */}
            <div
              ref={mosDotRef}
              className="absolute left-1/2 top-1/2 h-5 w-5 -translate-x-1/2 -translate-y-1/2 rounded-full"
              style={{
                background:
                  "radial-gradient(circle at 30% 30%, rgba(255,255,255,0.95), rgba(255,255,255,0.14) 35%, rgba(255,255,255,0) 66%), radial-gradient(circle at 60% 70%, rgba(183,255,78,0.92), rgba(0,209,255,0.42) 40%, rgba(255,61,154,0.26) 75%)",
                boxShadow:
                  "0 0 0 1px rgba(255,255,255,0.14) inset, 0 0 44px rgba(183,255,78,0.30), 0 18px 50px rgba(0,0,0,0.60)",
              }}
            />

            <div className="absolute left-4 bottom-4 right-4 flex items-center justify-between gap-3 text-white/40">
              <div className="font-mono text-[11px] tracking-[0.18em] uppercase">
                Wheel / drag
              </div>
              <div className="font-mono text-[11px] tracking-[0.18em] uppercase">
                Smooth response
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

