import { OverlayRegion, RenderOrientation, makeOverlayRegion } from './LayoutEngine';
import { makeDisplayRect } from './Geometry';

/** One stress-test bubble with its preferred orientation. */
export interface StressBubble {
  region: OverlayRegion;
  orientation: RenderOrientation;
}

/**
 * Built-in stress scene: 24 bubbles (20 vertical + 4 horizontal) over a
 * 1080x1520 canvas — the P0-5 fps acceptance vehicle (FR-015, SC-004).
 */
export class StressScene {
  static readonly CANVAS_W: number = 1080;
  static readonly CANVAS_H: number = 1520;

  static build(): Array<StressBubble> {
    const bubbles: Array<StressBubble> = [];
    const texts: Array<string> = [
      '今日も良い一日になりますように',
      'そうだね、頑張ろう！',
      '何か変な音がしなかった？',
      'ちょっと待って、後ろを見て',
      'この町の伝説を知っているか',
      'まさか本当だったなんて',
      '急いで逃げなければ',
      '大丈夫、僕が守るから',
      'それはずっと前の話だよ',
      '信じられない…なんてこと',
      '一起去看展览吧',
      '这个设定太有趣了',
      '别担心，慢慢来',
      '原来是这样啊',
      '那我们就出发吧',
      '谢谢你告诉我这些',
      '明天见，别忘了哦',
      '这里的风景真美',
      '快速的水平气泡用来测试横排路径',
      '好'
    ];
    // 4-column x 5-row grid of vertical bubbles + 4 horizontal bubbles at the bottom.
    const cols = 4;
    const rows = 5;
    const cellW = StressScene.CANVAS_W / cols;
    const cellH = 1000 / rows;
    let idx = 0;
    for (let r = 0; r < rows; r++) {
      for (let c = 0; c < cols; c++) {
        const text = texts[idx % texts.length];
        idx++;
        const box = makeDisplayRect(
          c * cellW + 24,
          r * cellH + 20,
          cellW - 48,
          cellH - 40
        );
        const region = makeOverlayRegion(box, text, StressScene.translateOf(idx));
        const bubble: StressBubble = { region: region, orientation: RenderOrientation.VERTICAL };
        bubbles.push(bubble);
      }
    }
    const hTexts: Array<string> = ['横排气泡一：验证水平排版', '横排气泡二：Binary Search Font', '横排气泡三', 'END'];
    for (let i = 0; i < hTexts.length; i++) {
      const box = makeDisplayRect(60 + i * 260, 1060, 240, 130);
      const region = makeOverlayRegion(box, hTexts[i], hTexts[i]);
      const bubble: StressBubble = { region: region, orientation: RenderOrientation.HORIZONTAL };
      bubbles.push(bubble);
    }
    // Two long vertical strips at the bottom to stress column stretching.
    const longText = '这一段很长的译文用于压测竖排列式排布与列距拉伸算法的极端情况表现是否正常';
    for (let i = 0; i < 2; i++) {
      const box = makeDisplayRect(120 + i * 520, 1220, 320, 260);
      const region = makeOverlayRegion(box, longText, longText);
      const bubble: StressBubble = { region: region, orientation: RenderOrientation.VERTICAL };
      bubbles.push(bubble);
    }
    return bubbles;
  }

  private static translateOf(seq: number): string {
    const zh: Array<string> = [
      '希望今天也是美好的一天',
      '是啊，加油吧！',
      '你有没有听到什么怪声音',
      '等等，看看后面',
      '你知道这个小镇的传说吗',
      '没想到竟然是真的',
      '必须赶紧逃跑',
      '没事的，有我保护你',
      '那是很久以前的事了',
      '难以置信……怎么会这样',
      '一起去看展览吧',
      '这个设定太有趣了',
      '别担心，慢慢来',
      '原来是这样啊',
      '那我们就出发吧',
      '谢谢你告诉我这些',
      '明天见，别忘了哦',
      '这里的风景真美',
      '快速的水平气泡用来测试横排路径',
      '好'
    ];
    return zh[(seq - 1) % zh.length];
  }
}
