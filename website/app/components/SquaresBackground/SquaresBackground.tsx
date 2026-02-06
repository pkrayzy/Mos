'use client';
import { useEffect, useRef } from 'react';

interface SquaresProps {
  direction?: 'right' | 'left' | 'up' | 'down' | 'diagonal';
  speed?: number;
  borderColor?: string;
  squareSize?: number;
  hoverFillColor?: string;
}

interface HoveredSquare {
  x: number;
  y: number;
}

function mod(n: number, m: number) {
  return ((n % m) + m) % m;
}

export function Squares({
  direction = 'right',
  speed = 1,
  borderColor = '#999',
  squareSize = 40,
  hoverFillColor = '#222',
}: SquaresProps) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const requestRef = useRef<number | null>(null);
  const gridOffset = useRef({ x: 0, y: 0 });
  const hoveredSquareRef = useRef<HoveredSquare | null>(null);
  const reducedMotionRef = useRef(false);
  const optionsRef = useRef({
    direction,
    speed,
    borderColor,
    squareSize,
    hoverFillColor,
  });

  useEffect(() => {
    optionsRef.current = { direction, speed, borderColor, squareSize, hoverFillColor };
  }, [direction, speed, borderColor, squareSize, hoverFillColor]);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const media = window.matchMedia?.('(prefers-reduced-motion: reduce)');
    const updateReducedMotion = () => {
      reducedMotionRef.current = Boolean(media?.matches);
    };
    updateReducedMotion();
    media?.addEventListener?.('change', updateReducedMotion);

    let cssWidth = 0;
    let cssHeight = 0;
    let gradient: CanvasGradient | null = null;

    const resizeCanvas = () => {
      const rect = canvas.getBoundingClientRect();
      cssWidth = Math.max(1, Math.floor(rect.width));
      cssHeight = Math.max(1, Math.floor(rect.height));

      const dpr = Math.max(1, window.devicePixelRatio || 1);
      canvas.width = Math.floor(cssWidth * dpr);
      canvas.height = Math.floor(cssHeight * dpr);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

      gradient = ctx.createRadialGradient(
        cssWidth / 2,
        cssHeight / 2,
        0,
        cssWidth / 2,
        cssHeight / 2,
        Math.sqrt(cssWidth * cssWidth + cssHeight * cssHeight) / 2
      );
      gradient.addColorStop(0, 'rgba(0, 0, 0, 0)');
      gradient.addColorStop(1, '#060606');
    };

    window.addEventListener('resize', resizeCanvas);
    resizeCanvas();

    const drawGrid = () => {
      const { borderColor, squareSize, hoverFillColor } = optionsRef.current;
      ctx.clearRect(0, 0, cssWidth, cssHeight);

      const offsetX = gridOffset.current.x;
      const offsetY = gridOffset.current.y;
      const hovered = hoveredSquareRef.current;

      ctx.strokeStyle = borderColor;

      for (let ix = 0, x = 0; x < cssWidth + squareSize; ix += 1, x += squareSize) {
        for (let iy = 0, y = 0; y < cssHeight + squareSize; iy += 1, y += squareSize) {
          const squareX = x - offsetX;
          const squareY = y - offsetY;

          if (
            hovered &&
            ix === hovered.x &&
            iy === hovered.y
          ) {
            ctx.fillStyle = hoverFillColor;
            ctx.fillRect(squareX, squareY, squareSize, squareSize);
          }

          ctx.strokeRect(squareX, squareY, squareSize, squareSize);
        }
      }

      if (gradient) {
        ctx.fillStyle = gradient;
        ctx.fillRect(0, 0, cssWidth, cssHeight);
      }
    };

    const updateAnimation = () => {
      const { direction, speed, squareSize } = optionsRef.current;
      const effectiveSpeed = reducedMotionRef.current ? 0 : Math.max(speed, 0.1);

      if (effectiveSpeed > 0) {
        switch (direction) {
          case 'right':
            gridOffset.current.x = mod(gridOffset.current.x - effectiveSpeed, squareSize);
            break;
          case 'left':
            gridOffset.current.x = mod(gridOffset.current.x + effectiveSpeed, squareSize);
            break;
          case 'up':
            gridOffset.current.y = mod(gridOffset.current.y + effectiveSpeed, squareSize);
            break;
          case 'down':
            gridOffset.current.y = mod(gridOffset.current.y - effectiveSpeed, squareSize);
            break;
          case 'diagonal':
            gridOffset.current.x = mod(gridOffset.current.x - effectiveSpeed, squareSize);
            gridOffset.current.y = mod(gridOffset.current.y - effectiveSpeed, squareSize);
            break;
        }
      }

      drawGrid();
      requestRef.current = requestAnimationFrame(updateAnimation);
    };

    const handlePointerMove = (event: PointerEvent) => {
      const rect = canvas.getBoundingClientRect();
      const mouseX = event.clientX - rect.left;
      const mouseY = event.clientY - rect.top;

      const { squareSize } = optionsRef.current;
      const hoveredX = Math.floor((mouseX + gridOffset.current.x) / squareSize);
      const hoveredY = Math.floor((mouseY + gridOffset.current.y) / squareSize);

      const current = hoveredSquareRef.current;
      if (!current || current.x !== hoveredX || current.y !== hoveredY) {
        hoveredSquareRef.current = { x: hoveredX, y: hoveredY };
      }
    };

    const handlePointerLeave = () => {
      hoveredSquareRef.current = null;
    };

    canvas.addEventListener('pointermove', handlePointerMove);
    canvas.addEventListener('pointerleave', handlePointerLeave);

    requestRef.current = requestAnimationFrame(updateAnimation);

    return () => {
      window.removeEventListener('resize', resizeCanvas);
      media?.removeEventListener?.('change', updateReducedMotion);
      if (requestRef.current) {
        cancelAnimationFrame(requestRef.current);
      }
      canvas.removeEventListener('pointermove', handlePointerMove);
      canvas.removeEventListener('pointerleave', handlePointerLeave);
    };
  }, []);

  return <canvas ref={canvasRef} className="w-full h-full border-none block"></canvas>;
}
