import { describe, it, expect } from '@ohos/hypium';
import { util } from '@kit.ArkTS';
import { naturalSort } from 'commons';
import {
  DisplayRect,
  FontSizeMode,
  LayoutEngine,
  RenderOptions,
  RenderOrientation,
  VerticalDirection,
  containFit,
  pixelToDisplay
} from 'corerender';
import { BingTranslator, SseParser } from 'coretranslate';
import { makePixelRect } from 'coremodel';

function toBuffer(bytes: Array<number>): ArrayBuffer {
  const arr = new Uint8Array(bytes.length);
  for (let i = 0; i < bytes.length; i++) {
    arr[i] = bytes[i] & 0xFF;
  }
  return arr.buffer;
}

function utf8Bytes(s: string): Array<number> {
  const encoded = new util.TextEncoder().encodeInto(s);
  const out: Array<number> = [];
  for (let i = 0; i < encoded.length; i++) {
    out.push(encoded[i]);
  }
  return out;
}

function renderOptions(orientation: RenderOrientation, mode: FontSizeMode, size: number): RenderOptions {
  const o: RenderOptions = {
    orientation: orientation,
    verticalDirection: VerticalDirection.RTL,
    fontSizeMode: mode,
    fixedFontSize: size,
    padding: 4
  };
  return o;
}

function makeBox(w: number, h: number): DisplayRect {
  const box: DisplayRect = { x: 0, y: 0, w: w, h: h };
  return box;
}

export default function localUnitTest() {
  describe('StarFlow local unit tests', () => {
    // ---------- T044: coordinate mapping ----------
    it('containFit_scales_and_centers', 0, () => {
      const fit = containFit(100, 200, 100, 100);
      expect(fit.scale).assertEqual(0.5);
      expect(fit.dx).assertEqual(25);
      expect(fit.dy).assertEqual(0);
    });

    it('pixelToDisplay_maps_box', 0, () => {
      const rect = pixelToDisplay(makePixelRect(10, 20, 30, 40), 0.5, 5, 5);
      expect(rect.x).assertEqual(10);
      expect(rect.y).assertEqual(15);
      expect(rect.w).assertEqual(15);
      expect(rect.h).assertEqual(20);
    });

    // ---------- T044: natural sort (v2 < v10) ----------
    it('naturalSort_numeric_aware', 0, () => {
      const sorted = naturalSort(['v10.jpg', 'v2.jpg', 'v1.jpg', 'v20.jpg']);
      expect(sorted[0]).assertEqual('v1.jpg');
      expect(sorted[1]).assertEqual('v2.jpg');
      expect(sorted[2]).assertEqual('v10.jpg');
      expect(sorted[3]).assertEqual('v20.jpg');
    });

    it('naturalSort_mixed_names', 0, () => {
      const sorted = naturalSort(['page-2.png', 'page-10.png', 'cover.png']);
      expect(sorted[0]).assertEqual('cover.png');
      expect(sorted[1]).assertEqual('page-2.png');
      expect(sorted[2]).assertEqual('page-10.png');
    });

    // ---------- T044: layout / ellipsis / font auto ----------
    it('layout_horizontal_auto_font_nonzero', 0, () => {
      const layout = LayoutEngine.layout('好', makeBox(120, 120),
        renderOptions(RenderOrientation.HORIZONTAL, FontSizeMode.AUTO, 16));
      expect(layout.runs.length).assertEqual(1);
      expect(layout.measuredFontSize >= 10).assertTrue();
    });

    it('layout_vertical_runs_per_char', 0, () => {
      const layout = LayoutEngine.layout('你好世界', makeBox(80, 240),
        renderOptions(RenderOrientation.VERTICAL, FontSizeMode.AUTO, 16));
      expect(layout.runs.length).assertEqual(4);
    });

    it('layout_fixed_font_overflow_truncates_with_ellipsis', 0, () => {
      const opts = renderOptions(RenderOrientation.HORIZONTAL, FontSizeMode.FIXED, 24);
      const layout = LayoutEngine.layout('这是一段很长很长的译文需要被截断处理不能拆行', makeBox(40, 28), opts);
      expect(layout.truncated).assertTrue();
      let last = '';
      if (layout.runs.length > 0) {
        last = layout.runs[layout.runs.length - 1].char;
      }
      expect(last).assertEqual('…');
    });

    it('layout_vertical_rtl_column_order', 0, () => {
      const opts = renderOptions(RenderOrientation.VERTICAL, FontSizeMode.FIXED, 20);
      const layout = LayoutEngine.layout('你好世界一二', makeBox(40, 60), opts);
      expect(layout.runs.length > 0).assertTrue();
    });

    // ---------- T045: SSE parsing ----------
    it('sse_single_event_and_done', 0, () => {
      const events: Array<string> = [];
      let done = false;
      const parser = new SseParser({
        onEvent: (data: string) => {
          events.push(data);
        },
        onDone: () => {
          done = true;
        }
      });
      parser.push(toBuffer(utf8Bytes('data: hello\n\n')));
      parser.push(toBuffer(utf8Bytes('data: [DONE]\n\n')));
      expect(events.length).assertEqual(1);
      expect(events[0]).assertEqual('hello');
      expect(done).assertTrue();
    });

    it('sse_multi_event_framing', 0, () => {
      const events: Array<string> = [];
      const parser = new SseParser({
        onEvent: (data: string) => {
          events.push(data);
        },
        onDone: () => {
        }
      });
      parser.push(toBuffer(utf8Bytes('data: a\n\ndata: b\n\n')));
      expect(events.length).assertEqual(2);
      expect(events[0]).assertEqual('a');
      expect(events[1]).assertEqual('b');
    });

    it('sse_cross_chunk_utf8_safe', 0, () => {
      const events: Array<string> = [];
      const parser = new SseParser({
        onEvent: (data: string) => {
          events.push(data);
        },
        onDone: () => {
        }
      });
      // "data: 日\n\n" — 日 = E6 97 A5, split so the 3 bytes span two chunks.
      const bytes = utf8Bytes('data: 日\n\n');
      const split = 7;
      parser.push(toBuffer(bytes.slice(0, split)));
      parser.push(toBuffer(bytes.slice(split)));
      expect(events.length).assertEqual(1);
      expect(events[0]).assertEqual('日');
    });

    // ---------- T045: Bing request assembly ----------
    it('bing_form_body_shape', 0, () => {
      const body = BingTranslator.buildFormBody('zh', 'en', '你好', 'tok123', 'key456');
      expect(body.indexOf('fromLang=zh-Hans') >= 0).assertTrue();
      expect(body.indexOf('to=en') >= 0).assertTrue();
      expect(body.indexOf(`text=${encodeURIComponent('你好')}`) >= 0).assertTrue();
      expect(body.indexOf('token=tok123') >= 0).assertTrue();
      expect(body.indexOf('key=key456') >= 0).assertTrue();
    });
  });
}
