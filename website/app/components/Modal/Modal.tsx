"use client";

import { ReactNode, useEffect, useId, useMemo, useRef } from "react";

function getFocusableElements(root: HTMLElement | null): HTMLElement[] {
  if (!root) return [];

  const nodes = Array.from(
    root.querySelectorAll<HTMLElement>(
      [
        'a[href]',
        'button:not([disabled])',
        'input:not([disabled])',
        'select:not([disabled])',
        'textarea:not([disabled])',
        '[tabindex]:not([tabindex="-1"])',
      ].join(",")
    )
  );

  return nodes.filter((el) => {
    // Filter out hidden elements.
    const style = window.getComputedStyle(el);
    return style.display !== "none" && style.visibility !== "hidden";
  });
}

interface ModalProps {
  isOpen: boolean;
  onClose: () => void;
  title: string;
  children: ReactNode;
  width?: string;
}

export function Modal({ isOpen, onClose, title, children, width = "max-w-sm" }: ModalProps) {
  const titleId = useId();
  const dialogRef = useRef<HTMLDivElement | null>(null);
  const closeButtonRef = useRef<HTMLButtonElement | null>(null);
  const lastActiveElementRef = useRef<HTMLElement | null>(null);

  const label = useMemo(() => ({ titleId }), [titleId]);

  useEffect(() => {
    if (!isOpen) return;

    lastActiveElementRef.current =
      document.activeElement instanceof HTMLElement ? document.activeElement : null;

    const prevOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";

    const raf = window.requestAnimationFrame(() => {
      const focusables = getFocusableElements(dialogRef.current);
      (closeButtonRef.current ?? focusables[0] ?? dialogRef.current)?.focus?.();
    });

    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        event.preventDefault();
        onClose();
        return;
      }
      if (event.key !== "Tab") return;

      const dialogEl = dialogRef.current;
      if (!dialogEl) return;

      const focusables = getFocusableElements(dialogEl);
      if (focusables.length === 0) {
        event.preventDefault();
        dialogEl.focus();
        return;
      }

      const first = focusables[0];
      const last = focusables[focusables.length - 1];
      const active = document.activeElement instanceof HTMLElement ? document.activeElement : null;

      if (event.shiftKey) {
        if (!active || !dialogEl.contains(active) || active === first) {
          event.preventDefault();
          last.focus();
        }
        return;
      }

      if (!active || !dialogEl.contains(active) || active === last) {
        event.preventDefault();
        first.focus();
      }
    };

    document.addEventListener("keydown", onKeyDown);

    return () => {
      window.cancelAnimationFrame(raf);
      document.body.style.overflow = prevOverflow;
      document.removeEventListener("keydown", onKeyDown);

      try {
        lastActiveElementRef.current?.focus?.();
      } catch {
        // Ignore focus restore failures (e.g. element unmounted).
      } finally {
        lastActiveElementRef.current = null;
      }
    };
  }, [isOpen, onClose]);

  return (
    <div
      className={`fixed inset-0 z-[60] flex items-center justify-center px-4
                 bg-black/55 backdrop-blur-md transition-opacity duration-500 ease-in-out
                 ${isOpen ? "opacity-100" : "opacity-0 pointer-events-none"}`}
      aria-hidden={!isOpen}
      onClick={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
      tabIndex={-1}
    >
      <div
        ref={dialogRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby={label.titleId}
        tabIndex={-1}
        className={`w-full ${width} rounded-[22px] border border-white/10
                 bg-[rgba(10,11,16,0.72)] shadow-elevated backdrop-blur-xl
                 transform transition-all duration-500 ease-in-out
                 ${isOpen ? "scale-100 opacity-100" : "scale-[0.98] opacity-0"}
                 motion-safe:animate-[modal-appear_0.5s_var(--ease-out)]`}
      >
        <div className="flex justify-between items-center px-5 sm:px-6 pt-5 sm:pt-6">
          <h3 id={label.titleId} className="font-display text-lg sm:text-xl text-white">
            {title}
          </h3>
          <button
            ref={closeButtonRef}
            type="button"
            onClick={onClose}
            className="rounded-xl p-2 text-white/55 hover:text-white/85 hover:bg-white/5 transition-colors"
            aria-label="Close dialog"
          >
            <svg
              className="w-6 h-6"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M6 18L18 6M6 6l12 12"
              />
            </svg>
          </button>
        </div>
        <div className="px-5 sm:px-6 pb-5 sm:pb-6 pt-4">{children}</div>
      </div>
    </div>
  );
}
