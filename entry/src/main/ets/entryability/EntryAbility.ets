/*
 * Copyright (c) 2026 StarFlowOhos contributors.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 */

import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppEnv } from '../common/AppEnv';
import { Log, ThemeTokens } from 'commons';

/** Purple Nocturne app shell: fixed dark color mode keeps system materials dark. */
export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    } catch (err) {
      Log.error('EntryAbility', `Failed to set colorMode. Cause: ${JSON.stringify(err)}`);
    }
    // Application-wide assembly: context, RDB init, engine registry,
    // local model path restore (plan: common/AppEnv.ets). Fire-and-forget;
    // pages await AppEnv.ready() before touching the database.
    AppEnv.init(this.context).catch((e: Object) => {
      Log.error('EntryAbility', `AppEnv init failed: ${e}`);
    });
    Log.info('EntryAbility', 'Ability onCreate');
  }

  onDestroy(): void {
    Log.info('EntryAbility', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    Log.info('EntryAbility', 'Ability onWindowStageCreate');
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        Log.error('EntryAbility', `Failed to load the content. Cause: ${JSON.stringify(err)}`);
        return;
      }
      Log.info('EntryAbility', 'Succeeded in loading the content.');
      this.configureWindow(windowStage);
    });
  }

  /**
   * System bar + window chrome: deep purple background, light status-bar icons.
   * Works for phone / tablet / 2in1 (window chrome is managed by the system on PC).
   */
  private configureWindow(windowStage: window.WindowStage): void {
    try {
      const mainWindow: window.Window = windowStage.getMainWindowSync();
      mainWindow.setWindowBackgroundColor(ThemeTokens.SURFACE);
      mainWindow.setWindowSystemBarProperties({
        statusBarColor: ThemeTokens.SURFACE,
        statusBarContentColor: '#FFFFFF',
        navigationBarColor: ThemeTokens.SURFACE,
        navigationBarContentColor: '#FFFFFF'
      }).catch((e: BusinessError) => {
        Log.warn('EntryAbility', `setWindowSystemBarProperties failed: ${e.message}`);
      });
    } catch (e) {
      Log.warn('EntryAbility', `configureWindow failed: ${e}`);
    }
  }

  onWindowStageDestroy(): void {
    Log.info('EntryAbility', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    Log.info('EntryAbility', 'Ability onForeground');
  }

  onBackground(): void {
    Log.info('EntryAbility', 'Ability onBackground');
  }
}
