import {
  Manga,
  OcrRegion,
  PageTranslation,
  TranslateStatus,
  makeOcrRegion,
  makePageTranslation,
  makePixelRect,
  MangaDao,
  PageDao,
  TranslationDao
} from 'coremodel';
import { AppEnv } from '../common/AppEnv';
import { MangaRepository } from '../data/MangaRepository';

/** One seeded bubble: original text + zh translation + original-pixel box. */
interface DemoBubble {
  text: string;
  zh: string;
  x: number;
  y: number;
  w: number;
  h: number;
}

const DEMO_MANGA_NAME = '示例漫画 · 紫夜';

/** Bubble boxes match the generated rawfile/demo/manga pages (1200x1700). */
const DEMO_PAGES: Array<Array<DemoBubble>> = [
  [
    { text: 'おはよう、今日もいい天気だね', zh: '早上好，今天天气也不错呢', x: 80, y: 90, w: 580, h: 240 },
    { text: 'そうだな…', zh: '是啊…', x: 760, y: 140, w: 360, h: 190 },
    { text: '学校に行く前に寄り道しよう', zh: '上学之前先绕道去个地方吧', x: 330, y: 1150, w: 750, h: 180 }
  ],
  [
    { text: 'ちょっと待って', zh: '等一下', x: 90, y: 200, w: 430, h: 320 },
    { text: 'もう遅刻するよ', zh: '要迟到了哦', x: 700, y: 580, w: 420, h: 220 },
    { text: '知ってる', zh: '我知道', x: 140, y: 1230, w: 420, h: 190 }
  ],
  [
    { text: 'この先は通行止めだ', zh: '前面禁止通行', x: 240, y: 120, w: 900, h: 180 },
    { text: 'え、どうして？', zh: '诶，为什么？', x: 90, y: 700, w: 510, h: 200 },
    { text: '工事をしているんだ', zh: '在施工呢', x: 560, y: 1080, w: 560, h: 210 }
  ],
  [
    { text: 'ここで少し休もう', zh: '在这里休息一下吧', x: 80, y: 120, w: 580, h: 220 },
    { text: 'いいね', zh: '不错', x: 820, y: 780, w: 310, h: 190 },
    { text: '明日もまた来よう', zh: '明天再来吧', x: 300, y: 1230, w: 780, h: 210 }
  ],
  [
    { text: '雨が降りそうだ', zh: '好像要下雨了', x: 120, y: 160, w: 520, h: 220 },
    { text: '傘を持ってきた？', zh: '带伞了吗？', x: 680, y: 640, w: 450, h: 220 },
    { text: '持ってない…', zh: '没带…', x: 120, y: 1180, w: 480, h: 210 }
  ],
  [
    { text: '大丈夫、走れば間に合う', zh: '没事，跑起来就赶得上了', x: 90, y: 110, w: 630, h: 220 },
    { text: '走るの？', zh: '跑？', x: 820, y: 760, w: 310, h: 220 },
    { text: 'いただきます', zh: '我开动了', x: 360, y: 1270, w: 540, h: 230 }
  ]
];

/**
 * Developer-only seeder for the P0-5 / export / history acceptance path.
 * The emulator has no Core Vision OCR service, so this writes realistic
 * page_translation rows (text + original-pixel boxes only — no bitmaps) so the
 * overlay renderer, "仅译文"/"双语" export and history pages can be verified
 * without a real device. It never ships as user-facing data.
 */
export class DemoTranslationSeeder {
  static async seed(): Promise<string> {
    await AppEnv.ready();
    const all = await MangaRepository.listAll();
    let manga: Manga | undefined = undefined;
    for (const item of all) {
      if (item.name === DEMO_MANGA_NAME) {
        manga = item;
        break;
      }
    }
    if (manga === undefined) {
      return '未找到示例漫画：请先在书架「生成示例漫画」';
    }
    const pages = await PageDao.queryByMangaId(manga.id);
    if (pages.length === 0) {
      return '示例漫画没有页面记录，请删除后重新生成';
    }
    let seededPages = 0;
    let seededBubbles = 0;
    for (const page of pages) {
      const bubbles = DEMO_PAGES[page.pageIndex % DEMO_PAGES.length];
      const regions: Array<OcrRegion> = [];
      const translations: Array<string> = [];
      for (const bubble of bubbles) {
        regions.push(makeOcrRegion(bubble.text,
          makePixelRect(bubble.x, bubble.y, bubble.w, bubble.h)));
        translations.push(bubble.zh);
      }
      const record: PageTranslation = makePageTranslation(page.id);
      record.engineType = 0;
      record.ocr = regions;
      record.translations = translations;
      record.status = TranslateStatus.DONE;
      await TranslationDao.upsert(record);
      await PageDao.updateTranslateStatus(page.id, TranslateStatus.DONE);
      seededPages++;
      seededBubbles += bubbles.length;
    }
    await MangaDao.updateTranslateStatus(manga.id, TranslateStatus.DONE);
    return '已注入示例译文：' + seededPages + ' 页 / ' + seededBubbles + ' 个气泡（含坐标，无位图）';
  }
}
