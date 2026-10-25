import { PixelRect } from 'coremodel';

/** Rect in display (view) coordinates. */
export interface DisplayRect {
  x: number;
  y: number;
  w: number;
  h: number;
}

/** Result of objectFit-contain fitting: uniform scale + centering offsets. */
export interface FitResult {
  scale: number;
  dx: number;
  dy: number;
}

export function makeDisplayRect(x: number, y: number, w: number, h: number): DisplayRect {
  const r: DisplayRect = { x: x, y: y, w: w, h: h };
  return r;
}

/**
 * Compute the contain-fit of a page (pageW x pageH) inside a view
 * (viewW x viewH): the largest uniform scale keeping aspect ratio,
 * plus offsets centering the scaled page (plan D5, unit-tested).
 */
export function containFit(pageW: number, pageH: number, viewW: number, viewH: number): FitResult {
  if (pageW <= 0 || pageH <= 0 || viewW <= 0 || viewH <= 0) {
    const fallback: FitResult = { scale: 1, dx: 0, dy: 0 };
    return fallback;
  }
  const scale = Math.min(viewW / pageW, viewH / pageH);
  const dx = (viewW - pageW * scale) / 2;
  const dy = (viewH - pageH * scale) / 2;
  const r: FitResult = { scale: scale, dx: dx, dy: dy };
  return r;
}

/** Map an original-pixel rect to display coordinates via a fit result. */
export function pixelToDisplay(box: PixelRect, scale: number, dx: number, dy: number): DisplayRect {
  return makeDisplayRect(
    box.x * scale + dx,
    box.y * scale + dy,
    box.w * scale,
    box.h * scale
  );
}
