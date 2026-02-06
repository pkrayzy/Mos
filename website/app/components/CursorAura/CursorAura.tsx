"use client";

import { useEffect, useRef, useState } from "react";

export function CursorAura({
  size = 220,
}: {
  size?: number;
}) {
  const ref = useRef<HTMLDivElement | null>(null);
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
    const el = ref.current;
    if (!el) return;

    let raf = 0;
    let x = window.innerWidth / 2;
    let y = window.innerHeight / 2;
    let tx = x;
    let ty = y;
    let s = 1;
    let ts = 1;

    const onMove = (event: PointerEvent) => {
      tx = event.clientX;
      ty = event.clientY;
    };
    const onDown = () => {
      ts = 0.9;
    };
    const onUp = () => {
      ts = 1;
    };

    window.addEventListener("pointermove", onMove, { passive: true });
    window.addEventListener("pointerdown", onDown, { passive: true });
    window.addEventListener("pointerup", onUp, { passive: true });

    const tick = () => {
      x += (tx - x) * 0.14;
      y += (ty - y) * 0.14;
      s += (ts - s) * 0.18;

      const dx = x - size / 2;
      const dy = y - size / 2;
      el.style.transform = `translate3d(${dx}px, ${dy}px, 0) scale(${s})`;

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
      ref={ref}
      aria-hidden="true"
      className="pointer-events-none fixed left-0 top-0 z-40 hidden sm:block"
      style={{
        width: size,
        height: size,
        transform: "translate3d(-9999px, -9999px, 0)",
        borderRadius: 999,
        mixBlendMode: "screen",
        opacity: 0.92,
        background:
          "radial-gradient(circle at 30% 30%, rgba(183,255,78,0.22), rgba(0,209,255,0.12) 42%, rgba(255,61,154,0.10) 68%, rgba(0,0,0,0) 72%)",
      }}
    />
  );
}
