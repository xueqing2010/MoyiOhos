/** 全局动效参数：统一时长/曲线，避免各页面动画节奏不一致。 */
export class Motion {
  static readonly FAST: number = 160;
  static readonly BASE: number = 260;
  static readonly SLOW: number = 360;

  /** 浮层/菜单出现：淡入 + 上滑。 */
  static overlay(): TransitionEffect {
    return TransitionEffect.OPACITY
      .animation({ duration: Motion.BASE, curve: Curve.EaseOut })
      .combine(TransitionEffect.translate({ y: 28 })
        .animation({ duration: Motion.BASE, curve: Curve.EaseOut }));
  }

  /** 页面/大块内容切换：淡入 + 轻微缩放。 */
  static content(): TransitionEffect {
    return TransitionEffect.OPACITY
      .animation({ duration: Motion.BASE, curve: Curve.EaseOut })
      .combine(TransitionEffect.scale({ x: 0.98, y: 0.98 })
        .animation({ duration: Motion.BASE, curve: Curve.EaseOut }));
  }

  /** 仅淡入淡出。 */
  static fade(): TransitionEffect {
    return TransitionEffect.OPACITY.animation({ duration: Motion.BASE, curve: Curve.EaseOut });
  }
}
