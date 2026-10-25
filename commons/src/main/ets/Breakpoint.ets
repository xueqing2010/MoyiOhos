import { display, mediaquery, window } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';

/**
 * One-time-development, multi-device sizing (一次开发，多端部署).
 * Official breakpoints: sm < 600vp, md 600–839vp, lg >= 840vp.
 */
export enum WindowSizeClass {
  SM = 0,
  MD = 1,
  LG = 2
}

/** Coarse hardware class used to tailor interaction (hover cursor etc.). */
export enum DeviceClass {
  PHONE = 0,
  TABLET = 1,
  PC = 2,
  OTHER = 3
}

export function sizeClassOfWidth(vp: number): WindowSizeClass {
  if (vp >= 840) {
    return WindowSizeClass.LG;
  }
  if (vp >= 600) {
    return WindowSizeClass.MD;
  }
  return WindowSizeClass.SM;
}

export function currentDeviceClass(): DeviceClass {
  const t = deviceInfo.deviceType;
  if (t === '2in1' || t === 'pc') {
    return DeviceClass.PC;
  }
  if (t === 'tablet') {
    return DeviceClass.TABLET;
  }
  if (t === 'phone' || t === 'default') {
    return DeviceClass.PHONE;
  }
  return DeviceClass.OTHER;
}

/** Screen width in vp (fallback / initial value before layout). */
export function screenWidthVp(): number {
  const d = display.getDefaultDisplaySync();
  const density = d.densityPixels > 0 ? d.densityPixels : 1;
  return d.width / density;
}

function vpWidthOfScreen(): number {
  return screenWidthVp();
}

/**
 * Reliable breakpoint observer for the app shell:
 * initial value is derived from the real display/window size (media queries can
 * report a pre-layout width on tablets), then updated on window resize.
 * Must be called from a UIAbility/UI page context.
 */
export async function startBreakpointObserver(context: common.Context,
  onChange: (c: WindowSizeClass) => void): Promise<() => void> {
  let win: window.Window | undefined = undefined;
  try {
    win = await window.getLastWindow(context);
  } catch (e) {
    win = undefined;
  }
  const apply = () => {
    let vp = vpWidthOfScreen();
    if (win !== undefined) {
      try {
        const rect = win.getWindowProperties().windowRect;
        const density = display.getDefaultDisplaySync().densityPixels;
        if (rect.width > 0 && density > 0) {
          vp = rect.width / density;
        }
      } catch (e) {
        // keep screen-derived fallback
      }
    }
    onChange(sizeClassOfWidth(vp));
  };
  apply();
  const sizeCb = (size: window.Size) => {
    const density = display.getDefaultDisplaySync().densityPixels;
    const vp = density > 0 ? size.width / density : size.width;
    onChange(sizeClassOfWidth(vp));
  };
  if (win !== undefined) {
    try {
      win.on('windowSizeChange', sizeCb);
    } catch (e) {
      // ignore and rely on media queries below
    }
  }
  const smListener = mediaquery.matchMediaSync('(width>=600vp)');
  const lgListener = mediaquery.matchMediaSync('(width>=840vp)');
  const emit = () => {
    let c = WindowSizeClass.SM;
    if (lgListener.matches) {
      c = WindowSizeClass.LG;
    } else if (smListener.matches) {
      c = WindowSizeClass.MD;
    }
    onChange(c);
  };
  smListener.on('change', emit);
  lgListener.on('change', emit);
  return () => {
    if (win !== undefined) {
      try {
        win.off('windowSizeChange', sizeCb);
      } catch (e) {
        // ignore
      }
    }
    smListener.off('change', emit);
    lgListener.off('change', emit);
  };
}

/**
 * Lightweight media-query observer (page level). Returns a stop function.
 */
export function observeBreakpoint(onChange: (c: WindowSizeClass) => void): () => void {
  const smListener = mediaquery.matchMediaSync('(width>=600vp)');
  const lgListener = mediaquery.matchMediaSync('(width>=840vp)');
  const emit = () => {
    let c = WindowSizeClass.SM;
    if (lgListener.matches) {
      c = WindowSizeClass.LG;
    } else if (smListener.matches) {
      c = WindowSizeClass.MD;
    }
    onChange(c);
  };
  smListener.on('change', emit);
  lgListener.on('change', emit);
  emit();
  return () => {
    smListener.off('change', emit);
    lgListener.off('change', emit);
  };
}
