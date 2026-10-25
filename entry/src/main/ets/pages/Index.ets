import { uiMaterial } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import {
  ThemeTokens,
  WindowSizeClass,
  sizeClassOfWidth,
  startBreakpointObserver,
  observeBreakpoint,
  screenWidthVp
} from 'commons';
import { AppEnv } from '../common/AppEnv';
import { Routes } from '../common/Routes';
import { SettingsRepository } from '../data/SettingsRepository';
import { ShelfView } from '../views/ShelfView';
import { ImportView } from '../views/ImportView';
import { TextTranslateView } from '../views/TextTranslateView';
import { HistoryView } from '../views/HistoryView';
import { MeView } from '../views/MeView';
import { SpikeWorkbenchPage } from '../pages/SpikeWorkbenchPage';
import { AboutPage } from '../pages/AboutPage';
import { SpikeImportPage } from '../pages/SpikeImportPage';
import { SpikeOcrPage } from '../pages/SpikeOcrPage';
import { SpikeRenderPage } from '../pages/SpikeRenderPage';
import { SpikeEnginePage } from '../pages/SpikeEnginePage';
import { SpikeNapiPage } from '../pages/SpikeNapiPage';
import { ModelManagerPage } from '../pages/ModelManagerPage';
import { ReaderPage } from '../pages/ReaderPage';
import { NovelReaderPage } from '../pages/NovelReaderPage';
import { NovelTocPage } from '../pages/NovelTocPage';
import { MangaTocPage } from '../pages/MangaTocPage';
import { ImportWizardPage } from '../pages/ImportWizardPage';
import { HistoryDetailPage } from '../pages/HistoryDetailPage';
import { HistoryFullscreenPage } from '../pages/HistoryFullscreenPage';
import { SettingsPage } from '../pages/SettingsPage';
import { SettingsReadingPage } from '../pages/SettingsReadingPage';
import { SettingsTranslatePage } from '../pages/SettingsTranslatePage';
import { SettingsOcrPage } from '../pages/SettingsOcrPage';
import { SettingsThemePage } from '../pages/SettingsThemePage';
import { ApiConfigPage } from '../pages/ApiConfigPage';
import { FaqPage } from '../pages/FaqPage';
import { OpenSourcePage } from '../pages/OpenSourcePage';
import { OnboardingPage } from '../pages/OnboardingPage';
import { ImageViewerPage } from '../pages/ImageViewerPage';
import { TextHistoryPage } from '../pages/TextHistoryPage';

/**
 * App shell (stage 2):
 *  · phone        → bottom Tabs with floating immersive light-sense bar
 *  · tablet / PC  → left navigation rail (一次开发，多端部署)
 * Navigation owns the global NavPathStack; feature pages are NavDestinations.
 */
@Entry
@Component
struct Index {
  @State currentTab: number = 0;
  @State sizeClass: WindowSizeClass = WindowSizeClass.SM;
  private immersiveSupported: boolean = false;
  private navStack: NavPathStack = AppEnv.getInstance().navStack;
  private stopBreakpoint: (() => void) | undefined = undefined;

  aboutToAppear(): void {
    this.immersiveSupported = uiMaterial.isImmersiveMaterialSupported();
    // Initial value from real screen size; refined by the root onAreaChange.
    this.sizeClass = sizeClassOfWidth(screenWidthVp());
    const ctx = getContext(this) as common.UIAbilityContext;
    startBreakpointObserver(ctx, (c: WindowSizeClass) => {
      this.sizeClass = c;
    }).then((stop: () => void) => {
      this.stopBreakpoint = stop;
    }).catch((e: Error) => {
      console.warn(`breakpoint observer fallback: ${e.message}`);
      this.stopBreakpoint = observeBreakpoint((c: WindowSizeClass) => {
        this.sizeClass = c;
      });
    });
    // First-launch guide: pushed after the Navigation stack is mounted.
    setTimeout(() => {
      this.maybeShowOnboarding();
    }, 700);
  }

  private async maybeShowOnboarding(): Promise<void> {
    try {
      const done = await SettingsRepository.isOnboardingDone();
      if (!done && this.navStack.size() === 0) {
        this.navStack.pushPathByName(Routes.ONBOARDING, '');
      }
    } catch (e) {
      console.warn(`onboarding check failed: ${e}`);
    }
  }

  aboutToDisappear(): void {
    if (this.stopBreakpoint !== undefined) {
      this.stopBreakpoint();
      this.stopBreakpoint = undefined;
    }
  }

  private isWide(): boolean {
    return this.sizeClass !== WindowSizeClass.SM;
  }

  @Builder
  phoneTab(index: number, icon: Resource, label: Resource) {
    Column() {
      Image(icon)
        .width(22)
        .height(22)
        .fillColor(this.currentTab === index ? ThemeTokens.PRIMARY : ThemeTokens.TEXT_HINT)
      Text(label)
        .fontSize(10)
        .fontColor(this.currentTab === index ? ThemeTokens.PRIMARY : ThemeTokens.TEXT_HINT)
        .margin({ top: 3 })
    }
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .height('100%')
  }

  @Builder
  railItem(index: number, icon: Resource, label: Resource) {
    if (this.sizeClass === WindowSizeClass.LG) {
      Row({ space: 12 }) {
        Image(icon)
          .width(22)
          .height(22)
          .fillColor(this.currentTab === index ? ThemeTokens.PRIMARY : ThemeTokens.TEXT_SECONDARY)
        Text(label)
          .fontSize(ThemeTokens.FONT_BODY)
          .fontWeight(this.currentTab === index ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.currentTab === index ? ThemeTokens.TEXT_PRIMARY : ThemeTokens.TEXT_SECONDARY)
      }
      .width('100%')
      .height(48)
      .padding({ left: 14, right: 14 })
      .borderRadius(ThemeTokens.RADIUS_SMALL)
      .backgroundColor(this.currentTab === index ? ThemeTokens.SURFACE_SECONDARY : Color.Transparent)
      .onClick(() => {
        this.currentTab = index;
      })
    } else {
      Column({ space: 3 }) {
        Image(icon)
          .width(22)
          .height(22)
          .fillColor(this.currentTab === index ? ThemeTokens.PRIMARY : ThemeTokens.TEXT_SECONDARY)
        Text(label)
          .fontSize(10)
          .fontColor(this.currentTab === index ? ThemeTokens.PRIMARY : ThemeTokens.TEXT_SECONDARY)
      }
      .justifyContent(FlexAlign.Center)
      .width('100%')
      .height(56)
      .margin({ top: 4 })
      .borderRadius(ThemeTokens.RADIUS_SMALL)
      .backgroundColor(this.currentTab === index ? ThemeTokens.SURFACE_SECONDARY : Color.Transparent)
      .onClick(() => {
        this.currentTab = index;
      })
    }
  }

  @Builder
  rail() {
    Column() {
      if (this.sizeClass === WindowSizeClass.LG) {
        Row({ space: 10 }) {
          Image($r('app.media.logo_starflow'))
            .width(34)
            .height(34)
          Column({ space: 1 }) {
            Text('星译')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(ThemeTokens.TEXT_PRIMARY)
            Text('StarFlow · HarmonyOS')
              .fontSize(9)
              .fontColor(ThemeTokens.TEXT_HINT)
          }
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding({ left: 10, right: 10, bottom: 18 })
      } else {
        Image($r('app.media.logo_starflow'))
          .width(34)
          .height(34)
          .margin({ bottom: 14 })
      }

      this.railItem(0, $r('app.media.ic_tab_shelf'), $r('app.string.tab_shelf_books'))
      this.railItem(1, $r('app.media.ic_tab_import'), $r('app.string.tab_import'))
      this.railItem(2, $r('app.media.ic_tab_translate'), $r('app.string.tab_translate'))
      this.railItem(3, $r('app.media.ic_tab_history'), $r('app.string.tab_history'))
      this.railItem(4, $r('app.media.ic_tab_me'), $r('app.string.tab_me'))

      Blank()
      Text('v1.1 · 紫夜')
        .fontSize(9)
        .fontColor(ThemeTokens.TEXT_TERTIARY)
        .margin({ bottom: 12 })
    }
    .width(this.sizeClass === WindowSizeClass.LG ? 216 : 88)
    .height('100%')
    .padding({ left: 10, right: 10, top: 14 })
    .backgroundColor(ThemeTokens.SURFACE_VARIANT)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  tabContent(index: number) {
    if (index === 0) {
      ShelfView()
    } else if (index === 1) {
      ImportView()
    } else if (index === 2) {
      TextTranslateView()
    } else if (index === 3) {
      HistoryView()
    } else {
      MeView()
    }
  }

  @Builder
  phoneTabContent(index: number) {
    Column() {
      this.tabContent(index)
    }
    .width('100%')
    .height('100%')
    .padding({ bottom: 84 })
    .backgroundColor(ThemeTokens.SURFACE)
  }

  @Builder
  phoneShell() {
    Tabs({ barPosition: BarPosition.End, index: this.currentTab }) {
      TabContent() {
        this.phoneTabContent(0)
      }
      .tabBar(this.phoneTab(0, $r('app.media.ic_tab_shelf'), $r('app.string.tab_shelf_books')))

      TabContent() {
        this.phoneTabContent(1)
      }
      .tabBar(this.phoneTab(1, $r('app.media.ic_tab_import'), $r('app.string.tab_import')))

      TabContent() {
        this.phoneTabContent(2)
      }
      .tabBar(this.phoneTab(2, $r('app.media.ic_tab_translate'), $r('app.string.tab_translate')))

      TabContent() {
        this.phoneTabContent(3)
      }
      .tabBar(this.phoneTab(3, $r('app.media.ic_tab_history'), $r('app.string.tab_history')))

      TabContent() {
        this.phoneTabContent(4)
      }
      .tabBar(this.phoneTab(4, $r('app.media.ic_tab_me'), $r('app.string.tab_me')))
    }
    .vertical(false)
    .barMode(BarMode.Fixed)
    .scrollable(true)
    .barHeight(64)
    .barOverlap(true)
    .barPosition(BarPosition.End)
    .barFloatingStyle({
      barBottomMargin: 10,
      systemMaterial: this.immersiveSupported
        ? new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.THIN,
          colorInvert: true,
          interactive: true
        })
        : undefined
    })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .onChange((index: number) => {
      this.currentTab = index;
    })
    .width('100%')
    .height('100%')
  }

  /**
   * Wide-screen content switch. Reads this.currentTab directly instead of
   * passing it into a @Builder parameter: ArkUI V1 builders capture parameters
   * by value, so a builder call with this.currentTab would never re-render
   * after the side rail changes the tab.
   */
  @Builder
  wideContent() {
    if (this.currentTab === 0) {
      ShelfView()
    } else if (this.currentTab === 1) {
      ImportView()
    } else if (this.currentTab === 2) {
      TextTranslateView()
    } else if (this.currentTab === 3) {
      HistoryView()
    } else {
      MeView()
    }
  }

  @Builder
  wideShell() {
    Row() {
      this.rail()
      Column() {
        this.wideContent()
      }
      .layoutWeight(1)
      .height('100%')
      .backgroundColor(ThemeTokens.SURFACE)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeTokens.SURFACE)
  }

  @Builder
  pageDestination(name: string) {
    if (name === Routes.SPIKE_WORKBENCH) {
      SpikeWorkbenchPage()
    } else if (name === Routes.ABOUT) {
      AboutPage()
    } else if (name === Routes.SPIKE_IMPORT) {
      SpikeImportPage()
    } else if (name === Routes.SPIKE_OCR) {
      SpikeOcrPage()
    } else if (name === Routes.SPIKE_RENDER) {
      SpikeRenderPage()
    } else if (name === Routes.SPIKE_ENGINE) {
      SpikeEnginePage()
    } else if (name === Routes.SPIKE_NAPI) {
      SpikeNapiPage()
    } else if (name === Routes.MODEL_MANAGER) {
      ModelManagerPage()
    } else if (name === Routes.READER) {
      ReaderPage()
    } else if (name === Routes.NOVEL_READER) {
      NovelReaderPage()
    } else if (name === Routes.NOVEL_TOC) {
      NovelTocPage()
    } else if (name === Routes.MANGA_TOC) {
      MangaTocPage()
    } else if (name === Routes.IMPORT_WIZARD) {
      ImportWizardPage()
    } else if (name === Routes.HISTORY_DETAIL) {
      HistoryDetailPage()
    } else if (name === Routes.HISTORY_FULLSCREEN) {
      HistoryFullscreenPage()
    } else if (name === Routes.SETTINGS) {
      SettingsPage()
    } else if (name === Routes.SETTINGS_READING) {
      SettingsReadingPage()
    } else if (name === Routes.SETTINGS_TRANSLATE) {
      SettingsTranslatePage()
    } else if (name === Routes.SETTINGS_OCR) {
      SettingsOcrPage()
    } else if (name === Routes.SETTINGS_THEME) {
      SettingsThemePage()
    } else if (name === Routes.API_CONFIG) {
      ApiConfigPage()
    } else if (name === Routes.FAQ) {
      FaqPage()
    } else if (name === Routes.OPEN_SOURCE) {
      OpenSourcePage()
    } else if (name === Routes.ONBOARDING) {
      OnboardingPage()
    } else if (name === Routes.IMAGE_VIEWER) {
      ImageViewerPage()
    } else if (name === Routes.TEXT_HISTORY) {
      TextHistoryPage()
    } else {
      Column({ space: ThemeTokens.PAGE_PADDING }) {
        Text('页面建设中')
          .fontSize(ThemeTokens.FONT_TITLE)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
        Text(`路由：${name}`)
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontColor(ThemeTokens.TEXT_HINT)
      }
      .justifyContent(FlexAlign.Center)
      .width('100%')
      .height('100%')
      .backgroundColor(ThemeTokens.SURFACE)
    }
  }

  build() {
    Navigation(this.navStack) {
      if (this.isWide()) {
        this.wideShell()
      } else {
        this.phoneShell()
      }
    }
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .navDestination(this.pageDestination)
    .backgroundColor(ThemeTokens.SURFACE)
    .width('100%')
    .height('100%')
    .onAreaChange((oldArea: Area, newArea: Area) => {
      const width = newArea.width as number;
      if (width > 0) {
        this.sizeClass = sizeClassOfWidth(width);
      }
    })
  }
}