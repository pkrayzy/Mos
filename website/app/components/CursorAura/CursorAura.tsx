"use client";

import { useEffect, useRef, useState } from "react";

function clamp(n: number, min: number, max: number) {
  return Math.min(max, Math.max(min, n));
}

function lerp(a: number, b: number, t: number) {
  return a + (b - a) * t;
}

export function CursorAura({
  size = 220,
}: {
  size?: number;
}) {
  const outerRef = useRef<HTMLDivElement | null>(null);
  const innerRef = useRef<HTMLDivElement | null>(null);
  const [enabled, setEnabled] = useState(false);

  useEffect(() => {
    const fine = window.matchMedia?.("(pointer: fine)")?.matches ?? false;
    const reduced = window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches ?? false;
    const raf = window.requestAnimationFrame(() => {
      setEnabled(Boolean(fine && !reduced));
    });
    return () => window.cancelAnimationFrame(raf);
  }, []);

  useEffect(() => {
    if (!enabled) return;
    const outer = outerRef.current;
    const inner = innerRef.current;
    if (!outer || !inner) return;

    let raf = 0;
    let tx = window.innerWidth / 2;
    let ty = window.innerHeight / 2;
    let ix = tx;
    let iy = ty;
    let ox = tx;
    let oy = ty;
    let press = 1;
    let targetPress = 1;
    let last = performance.now();

    const onMove = (event: PointerEvent) => {
      tx = event.clientX;
      ty = event.clientY;
    };
    const onDown = () => {
      targetPress = 0.92;
    };
    const onUp = () => {
      targetPress = 1;
    };

    window.addEventListener("pointermove", onMove, { passive: true });
    window.addEventListener("pointerdown", onDown, { passive: true });
    window.addEventListener("pointerup", onUp, { passive: true });

    const apply = (
      el: HTMLDivElement,
      x: number,
      y: number,
      vx: number,
      vy: number,
      elSize: number,
      baseOpacity: number,
      baseBlur: number,
      stretchScale: number
    ) => {
      const speed = Math.hypot(vx, vy); // px/s
      const speedN = clamp(speed / 1700, 0, 1);
      const angle = Math.atan2(vy, vx) * (180 / Math.PI);

      const stretch = speedN * stretchScale;
      const sx = 1 + stretch;
      const sy = 1 - stretch * 0.62;

      // Specular highlight drifts toward the movement direction.
      const vxN = clamp(vx / 1600, -1, 1);
      const vyN = clamp(vy / 1600, -1, 1);
      const offset = 12 + speedN * 10;
      const hx = clamp(50 + vxN * offset, 18, 82);
      const hy = clamp(50 + vyN * offset, 18, 82);

      const o = clamp(baseOpacity + speedN * 0.12, 0.05, 0.95);
      const blur = baseBlur + speedN * 10;

      const dx = x - elSize / 2;
      const dy = y - elSize / 2;
      el.style.setProperty("--hx", `${hx.toFixed(2)}%`);
      el.style.setProperty("--hy", `${hy.toFixed(2)}%`);
      el.style.setProperty("--blur", `${blur.toFixed(2)}px`);
      el.style.setProperty("--o", o.toFixed(3));
      el.style.transform = `translate3d(${dx.toFixed(2)}px, ${dy.toFixed(2)}px, 0) rotate(${angle.toFixed(2)}deg) scaleX(${(sx * press).toFixed(3)}) scaleY(${(sy * press).toFixed(3)})`;
    };

    const tick = (now: number) => {
      const dt = clamp((now - last) / 1000, 1 / 240, 1 / 20);
      last = now;

      const pix = ix;
      const piy = iy;
      const pox = ox;
      const poy = oy;

      // Inner follows faster, outer lags for a tail feel.
      ix = lerp(ix, tx, 0.22);
      iy = lerp(iy, ty, 0.22);
      ox = lerp(ox, tx, 0.11);
      oy = lerp(oy, ty, 0.11);

      press = lerp(press, targetPress, 0.18);

      const ivx = (ix - pix) / dt;
      const ivy = (iy - piy) / dt;
      const ovx = (ox - pox) / dt;
      const ovy = (oy - poy) / dt;

      apply(outer, ox, oy, ovx, ovy, size * 1.75, 0.38, 18, 0.14);
      apply(inner, ix, iy, ivx, ivy, size, 0.68, 2, 0.22);

      raf = window.requestAnimationFrame(tick);
    };
    raf = window.requestAnimationFrame(tick);

    return () => {
      window.cancelAnimationFrame(raf);
      window.removeEventListener("pointermove", onMove);
      window.removeEventListener("pointerdown", onDown);
      window.removeEventListener("pointerup", onUp);
    };
  }, [enabled, size]);

  if (!enabled) return null;

  return (
    <div
      aria-hidden="true"
      className="pointer-events-none fixed left-0 top-0 z-40 hidden sm:block"
    >
      <div
        ref={outerRef}
        style={{
          width: size * 1.75,
          height: size * 1.75,
          transform: "translate3d(-9999px, -9999px, 0)",
          borderRadius: 999,
          mixBlendMode: "screen",
          opacity: 0.4,
          filter: "blur(var(--blur, 18px))",
          background:
            "radial-gradient(240px 240px at var(--hx, 50%) var(--hy, 50%), rgba(255,255,255,0.12), rgba(255,255,255,0.06) 38%, rgba(255,255,255,0.03) 62%, rgba(0,0,0,0) 74%)",
          willChange: "transform, opacity, filter",
        }}
      />
      <div
        ref={innerRef}
        style={{
          position: "absolute",
          left: 0,
          top: 0,
          width: size,
          height: size,
          transform: "translate3d(-9999px, -9999px, 0)",
          borderRadius: 999,
          mixBlendMode: "screen",
          opacity: 0.75,
          filter: "blur(var(--blur, 2px))",
          background:
            "radial-gradient(120px 120px at var(--hx, 52%) var(--hy, 42%), rgba(255,255,255,0.26), rgba(255,255,255,0.13) 32%, rgba(255,255,255,0.07) 52%, rgba(0,0,0,0) 70%), radial-gradient(circle at 50% 55%, rgba(255,255,255,0.10), rgba(255,255,255,0.05) 48%, rgba(0,0,0,0) 74%)",
          willChange: "transform, opacity, filter",
        }}
      />
    </div>
  );
}
