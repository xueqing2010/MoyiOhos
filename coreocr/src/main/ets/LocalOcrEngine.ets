import { image } from '@kit.ImageKit';
import fs from '@ohos.file.fs';
import { OnnxEnvironment, OnnxTensor, OnnxResult, OnnxSession, OnnxValue, TensorInfo } from '@ohos/onnxruntime';
import { Log, toMediaUri } from 'commons';
import { OcrRegion, makeOcrRegion, makePixelRect } from 'coremodel';
const TAG = 'LocalOcrEngine';
// 768 足够识别漫画气泡文字，同时比 960 少约 36% 检测像素；
// 实测把整页 OCR 从 2.6s 降到约 1.7s。
const DET_MAX_SIDE = 768;
const DET_THRESH = 0.3;
const DET_MIN_SIZE = 4;
const REC_HEIGHT = 48;
export interface LocalOcrConfig {
    detPath: string;
    recPath: string;
    dictText: string;
}
class PagePixels {
    width: number = 0;
    height: number = 0;
    rgba: Uint8Array = new Uint8Array(0);
}
class CandidateBox {
    x: number = 0;
    y: number = 0;
    w: number = 0;
    h: number = 0;
}
/**
 * 本地 PP-OCRv6 推理（ONNX Runtime OHOS NAPI）：det 文本检测 + rec CTC 识别。
 * 模型由用户在设置中可选下载；字典随安装包（上游 ppocrv6_dict.txt）。
 * 后处理做了轻量实现：3x3 膨胀 + 连通域 + 轴对齐框，适合漫画气泡文本行。
 */
export class LocalOcrEngine {
    private static instance: LocalOcrEngine = new LocalOcrEngine();
    private detSession: OnnxSession | undefined = undefined;
    private recSession: OnnxSession | undefined = undefined;
    private dict: Array<string> = [];
    private envReady: boolean = false;
    private configKey: string = '';
    static getInstance(): LocalOcrEngine {
        return LocalOcrEngine.instance;
    }
    isReady(): boolean {
        return this.detSession !== undefined && this.recSession !== undefined;
    }
    /** 加载/复用会话；配置变化才重建。 */
    async init(config: LocalOcrConfig): Promise<void> {
        const key = config.detPath + '|' + config.recPath;
        if (this.isReady() && key === this.configKey) {
            return;
        }
        this.release();
        if (!this.envReady) {
            try {
                OnnxEnvironment.InitEnvironment();
            }
            catch (e) {
                const msg = (e as Error).message ?? '';
                // ONNX Runtime 环境是进程级的；另一个线程初始化过后这里会抛
                // "already initialized"，此时直接复用即可，不能当成失败。
                if (msg.indexOf('already initialized') < 0) {
                    throw new Error(msg.length > 0 ? msg : 'ONNX Runtime 初始化失败');
                }
                Log.warn(TAG, 'ORT environment already initialized by another thread');
            }
            // 张量构造自检：验证 NAPI 环境/分配器已就绪（否则会在构造时空指针）。
            const probe = new OnnxTensor(new ArrayBuffer(12), [3], 0);
            probe.Close();
            this.envReady = true;
            Log.info(TAG, 'ORT environment ready, version=' + OnnxEnvironment.GetVersion());
        }
        const t0 = Date.now();
        try {
            this.detSession = OnnxEnvironment.CreateSessionFromModelFile(config.detPath);
            this.recSession = OnnxEnvironment.CreateSessionFromModelFile(config.recPath);
        }
        catch (e) {
            this.release();
            const err = e as Error;
            const detail = err !== undefined && err.message !== undefined ? err.message : JSON.stringify(e);
            Log.error(TAG, 'OCR model load failed: ' + detail);
            throw new Error('本地 OCR 模型加载失败：' + detail + '（请重新下载 det/rec 模型）');
        }
        const lines = config.dictText.split('\n');
        // CTC class 0 = blank；字典文件第一行才是第一个真实字符，需前置 blank。
        const dict: Array<string> = [''];
        for (const line of lines) {
            const ch = line.endsWith('\r') ? line.substring(0, line.length - 1) : line;
            if (ch.length > 0) {
                dict.push(ch);
            }
        }
        this.dict = dict;
        this.configKey = key;
        Log.info(TAG, 'OCR sessions ready in ' + (Date.now() - t0) + 'ms, dict=' + dict.length);
    }
    release(): void {
        try {
            if (this.detSession !== undefined) {
                this.detSession.Close();
            }
        }
        catch (e) {
        }
        try {
            if (this.recSession !== undefined) {
                this.recSession.Close();
            }
        }
        catch (e) {
        }
        this.detSession = undefined;
        this.recSession = undefined;
        this.dict = [];
        this.configKey = '';
    }
    /** 仅跑 det，返回扁平框 [x,y,w,h,...]；供 Entry 原生 rec 异步使用。 */
    async detectBoxes(pagePath: string): Promise<Array<number>> {
        if (this.detSession === undefined) {
            throw new Error('本地 OCR 检测模型尚未初始化');
        }
        const page = await this.loadPixels(pagePath);
        const boxes = this.detect(page);
        const out: Array<number> = [];
        for (const box of boxes) {
            out.push(box.x);
            out.push(box.y);
            out.push(box.w);
            out.push(box.h);
        }
        return out;
    }

    async recognize(pagePath: string): Promise<Array<OcrRegion>> {
        if (!this.isReady()) {
            throw new Error('本地 OCR 尚未初始化');
        }
        const page = await this.loadPixels(pagePath);
        if (page.width <= 0 || page.height <= 0) {
            throw new Error('页面图像解码失败');
        }
        const t0 = Date.now();
        const boxes = this.detect(page);
        Log.info(TAG, 'det boxes=' + boxes.length + ' in ' + (Date.now() - t0) + 'ms');
        const regions: Array<OcrRegion> = [];
        for (const box of boxes) {
            try {
                const text = this.recognizeBox(page, box);
                const trimmed = text.trim();
                const area = box.w * box.h;
                const pageArea = page.width * page.height;
                // 过滤整页大框，以及“单字却占大面积”的伪检测（暗色背景/线稿误检）。
                if (trimmed.length === 0 || area > pageArea * 0.15
                    || (trimmed.length <= 2 && area > pageArea * 0.04)) {
                    Log.warn(TAG, 'skip suspicious box ' + box.w + 'x' + box.h + ' text=' + trimmed);
                    continue;
                }
                regions.push(makeOcrRegion(trimmed, makePixelRect(box.x, box.y, box.w, box.h)));
            }
            catch (e) {
                Log.warn(TAG, 'rec box failed: ' + JSON.stringify(e));
            }
        }
        regions.sort((a: OcrRegion, b: OcrRegion): number => {
            if (Math.abs(a.box.y - b.box.y) > 12) {
                return a.box.y - b.box.y;
            }
            return a.box.x - b.box.x;
        });
        Log.info(TAG, 'local OCR lines=' + regions.length + ', total=' + (Date.now() - t0) + 'ms');
        return regions;
    }
    private async loadPixels(pagePath: string): Promise<PagePixels> {
        const out = new PagePixels();
        let source: image.ImageSource | undefined = undefined;
        let file: fs.File | undefined = undefined;
        try {
            try {
                source = image.createImageSource(toMediaUri(pagePath));
            }
            catch (e) {
                source = undefined;
            }
            if (source === undefined || source === null) {
                file = fs.openSync(pagePath, fs.OpenMode.READ_ONLY);
                source = image.createImageSource(file.fd);
            }
            if (source === undefined || source === null) {
                throw new Error('无法打开页面图片');
            }
            const pm = await source.createPixelMap();
            if (pm === undefined || pm === null) {
                throw new Error('无法创建页面像素图');
            }
            const info = await pm.getImageInfo();
            out.width = info.size.width;
            out.height = info.size.height;
            const buffer = new ArrayBuffer(out.width * out.height * 4);
            await pm.readPixelsToBuffer(buffer);
            out.rgba = new Uint8Array(buffer);
            pm.release();
            return out;
        }
        finally {
            if (source !== undefined) {
                source.release();
            }
            if (file !== undefined) {
                fs.closeSync(file);
            }
        }
    }
    private detect(page: PagePixels): Array<CandidateBox> {
        let scale = 1;
        const maxSide = Math.max(page.width, page.height);
        if (maxSide > DET_MAX_SIDE) {
            scale = DET_MAX_SIDE / maxSide;
        }
        const detW = Math.max(32, Math.round(page.width * scale / 32) * 32);
        const detH = Math.max(32, Math.round(page.height * scale / 32) * 32);
        const input = new Float32Array(3 * detH * detW);
        this.resizeToCHW(page, detW, detH, input);
        const detBuffer = new ArrayBuffer(input.length * 4);
        new Float32Array(detBuffer).set(input);
        const detShape: number[] = [1, 3, detH, detW];
        const tensor = new OnnxTensor(detBuffer, detShape, 0);
        let result: OnnxResult | undefined = undefined;
        try {
            const inputs: Record<string, OnnxValue> = {};
            inputs['x'] = tensor;
            result = this.detSession!.Run(inputs);
            const outName = this.detSession!.GetOutputNames()[0];
            const outValue = result.GetValueByName(outName);
            if (outValue.GetType() !== 1) {
                return [];
            }
            const outTensor = outValue as OnnxTensor;
            const info: TensorInfo = outTensor.GetInfo();
            const shape: number[] = info.GetShape();
            const predH = shape[shape.length - 2];
            const predW = shape[shape.length - 1];
            const data = new Float32Array(outTensor.GetDataAsArrayBuffer());
            return this.components(data, predW, predH, page.width, page.height);
        }
        finally {
            tensor.Close();
            if (result !== undefined) {
                result.Close();
            }
        }
    }
    /** 3x3 膨胀 + 连通域 + 轴对齐框（映射回原图坐标）。 */
    private components(data: Float32Array, predW: number, predH: number, srcW: number, srcH: number): Array<CandidateBox> {
        const mask = new Uint8Array(predW * predH);
        for (let i = 0; i < mask.length; i++) {
            mask[i] = data[i] > DET_THRESH ? 1 : 0;
        }
        // 可分离膨胀（半径 3），把相邻笔画/字符连成文本行；竖排日文也能连上。
        const radius = 3;
        const tmp = new Uint8Array(mask.length);
        for (let y = 0; y < predH; y++) {
            for (let x = 0; x < predW; x++) {
                if (mask[y * predW + x] === 0) {
                    continue;
                }
                const x0 = Math.max(0, x - radius);
                const x1 = Math.min(predW - 1, x + radius);
                for (let nx = x0; nx <= x1; nx++) {
                    tmp[y * predW + nx] = 1;
                }
            }
        }
        const dilated = new Uint8Array(mask.length);
        for (let y = 0; y < predH; y++) {
            for (let x = 0; x < predW; x++) {
                if (tmp[y * predW + x] === 0) {
                    continue;
                }
                const y0 = Math.max(0, y - radius);
                const y1 = Math.min(predH - 1, y + radius);
                for (let ny = y0; ny <= y1; ny++) {
                    dilated[ny * predW + x] = 1;
                }
            }
        }
        const visited = new Uint8Array(dilated.length);
        const stack: Array<number> = [];
        const boxes: Array<CandidateBox> = [];
        const sx = srcW / predW;
        const sy = srcH / predH;
        for (let i = 0; i < dilated.length; i++) {
            if (dilated[i] === 0 || visited[i] === 1) {
                continue;
            }
            let minX = predW;
            let maxX = 0;
            let minY = predH;
            let maxY = 0;
            let count = 0;
            stack.push(i);
            visited[i] = 1;
            while (stack.length > 0) {
                const idx = stack.pop() as number;
                const x = idx % predW;
                const y = Math.floor(idx / predW);
                count++;
                if (x < minX) {
                    minX = x;
                }
                if (x > maxX) {
                    maxX = x;
                }
                if (y < minY) {
                    minY = y;
                }
                if (y > maxY) {
                    maxY = y;
                }
                if (x > 0 && dilated[idx - 1] === 1 && visited[idx - 1] === 0) {
                    visited[idx - 1] = 1;
                    stack.push(idx - 1);
                }
                if (x + 1 < predW && dilated[idx + 1] === 1 && visited[idx + 1] === 0) {
                    visited[idx + 1] = 1;
                    stack.push(idx + 1);
                }
                if (y > 0 && dilated[idx - predW] === 1 && visited[idx - predW] === 0) {
                    visited[idx - predW] = 1;
                    stack.push(idx - predW);
                }
                if (y + 1 < predH && dilated[idx + predW] === 1 && visited[idx + predW] === 0) {
                    visited[idx + predW] = 1;
                    stack.push(idx + predW);
                }
            }
            if (count < 12) {
                continue;
            }
            const box = new CandidateBox();
            box.x = Math.max(0, Math.floor(minX * sx));
            box.y = Math.max(0, Math.floor(minY * sy));
            box.w = Math.min(srcW - box.x, Math.ceil((maxX - minX + 1) * sx));
            box.h = Math.min(srcH - box.y, Math.ceil((maxY - minY + 1) * sy));
            if (box.w < DET_MIN_SIZE || box.h < DET_MIN_SIZE) {
                continue;
            }
            // unclip 近似：向外扩 12%，把紧贴的笔画/气泡边距包进识别框。
            const ex = Math.round(box.w * 0.12);
            const ey = Math.round(box.h * 0.12);
            box.x = Math.max(0, box.x - ex);
            box.y = Math.max(0, box.y - ey);
            box.w = Math.min(srcW - box.x, box.w + ex * 2);
            box.h = Math.min(srcH - box.y, box.h + ey * 2);
            boxes.push(box);
            if (boxes.length >= 80) {
                break;
            }
        }
        // 合并相近/重叠框，避免同一行被拆成字符碎片。
        let changed = true;
        while (changed) {
            changed = false;
            for (let i = 0; i < boxes.length; i++) {
                for (let j = i + 1; j < boxes.length; j++) {
                    const a = boxes[i];
                    const b = boxes[j];
                    const gap = 8;
                    const near = a.x - gap <= b.x + b.w && b.x - gap <= a.x + a.w
                        && a.y - gap <= b.y + b.h && b.y - gap <= a.y + a.h;
                    if (near) {
                        const x0 = Math.min(a.x, b.x);
                        const y0 = Math.min(a.y, b.y);
                        const x1 = Math.max(a.x + a.w, b.x + b.w);
                        const y1 = Math.max(a.y + a.h, b.y + b.h);
                        a.x = x0;
                        a.y = y0;
                        a.w = x1 - x0;
                        a.h = y1 - y0;
                        boxes.splice(j, 1);
                        changed = true;
                        break;
                    }
                }
                if (changed) {
                    break;
                }
            }
        }
        return boxes;
    }
    private recognizeBox(page: PagePixels, box: CandidateBox): string {
        const pad = 2;
        const x0 = Math.max(0, box.x - pad);
        const y0 = Math.max(0, box.y - pad);
        const x1 = Math.min(page.width, box.x + box.w + pad);
        const y1 = Math.min(page.height, box.y + box.h + pad);
        const cropW = Math.max(1, x1 - x0);
        const cropH = Math.max(1, y1 - y0);
        let recW = Math.ceil(REC_HEIGHT * cropW / cropH);
        recW = Math.max(32, Math.ceil(recW / 32) * 32);
        recW = Math.min(recW, 1280);
        const input = new Float32Array(3 * REC_HEIGHT * recW);
        for (let y = 0; y < REC_HEIGHT; y++) {
            const sy = y0 + (y + 0.5) * cropH / REC_HEIGHT - 0.5;
            for (let x = 0; x < recW; x++) {
                if (x >= Math.ceil(REC_HEIGHT * cropW / cropH)) {
                    continue;
                }
                const sx = x0 + (x + 0.5) * cropW / Math.ceil(REC_HEIGHT * cropW / cropH) - 0.5;
                const rgb = this.sample(page, sx, sy);
                const base = y * recW + x;
                input[0 * REC_HEIGHT * recW + base] = (rgb[0] / 255 - 0.5) / 0.5;
                input[1 * REC_HEIGHT * recW + base] = (rgb[1] / 255 - 0.5) / 0.5;
                input[2 * REC_HEIGHT * recW + base] = (rgb[2] / 255 - 0.5) / 0.5;
            }
        }
        const recBuffer = new ArrayBuffer(input.length * 4);
        new Float32Array(recBuffer).set(input);
        const recShape: number[] = [1, 3, REC_HEIGHT, recW];
        const tensor = new OnnxTensor(recBuffer, recShape, 0);
        let result: OnnxResult | undefined = undefined;
        try {
            const inputs: Record<string, OnnxValue> = {};
            inputs['x'] = tensor;
            result = this.recSession!.Run(inputs);
            const outName = this.recSession!.GetOutputNames()[0];
            const outValue = result.GetValueByName(outName);
            if (outValue.GetType() !== 1) {
                return '';
            }
            const outTensor = outValue as OnnxTensor;
            const info: TensorInfo = outTensor.GetInfo();
            const shape: number[] = info.GetShape();
            const seqLen = shape[shape.length - 2];
            const classes = shape[shape.length - 1];
            const data = new Float32Array(outTensor.GetDataAsArrayBuffer());
            let text = '';
            let previous = -1;
            for (let t = 0; t < seqLen; t++) {
                const offset = t * classes;
                let best = 0;
                let prob = data[offset];
                for (let c = 1; c < classes; c++) {
                    if (data[offset + c] > prob) {
                        best = c;
                        prob = data[offset + c];
                    }
                }
                if (best > 0 && best !== previous && best < this.dict.length) {
                    text += this.dict[best];
                }
                previous = best;
            }
            return text;
        }
        finally {
            tensor.Close();
            if (result !== undefined) {
                result.Close();
            }
        }
    }
    private resizeToCHW(page: PagePixels, dstW: number, dstH: number, out: Float32Array): void {
        const plane = dstW * dstH;
        for (let y = 0; y < dstH; y++) {
            const sy = (y + 0.5) * page.height / dstH - 0.5;
            for (let x = 0; x < dstW; x++) {
                const sx = (x + 0.5) * page.width / dstW - 0.5;
                const rgb = this.sample(page, sx, sy);
                const idx = y * dstW + x;
                out[idx] = (rgb[0] / 255 - 0.5) / 0.5;
                out[plane + idx] = (rgb[1] / 255 - 0.5) / 0.5;
                out[plane * 2 + idx] = (rgb[2] / 255 - 0.5) / 0.5;
            }
        }
    }
    private sample(page: PagePixels, fx: number, fy: number): Array<number> {
        const x = Math.max(0, Math.min(page.width - 1, fx));
        const y = Math.max(0, Math.min(page.height - 1, fy));
        const x0 = Math.floor(x);
        const y0 = Math.floor(y);
        const x1 = Math.min(page.width - 1, x0 + 1);
        const y1 = Math.min(page.height - 1, y0 + 1);
        const wx = x - x0;
        const wy = y - y0;
        const i00 = (y0 * page.width + x0) * 4;
        const i10 = (y0 * page.width + x1) * 4;
        const i01 = (y1 * page.width + x0) * 4;
        const i11 = (y1 * page.width + x1) * 4;
        const out: Array<number> = [0, 0, 0];
        for (let c = 0; c < 3; c++) {
            const top = page.rgba[i00 + c] * (1 - wx) + page.rgba[i10 + c] * wx;
            const bottom = page.rgba[i01 + c] * (1 - wx) + page.rgba[i11 + c] * wx;
            out[c] = top * (1 - wy) + bottom * wy;
        }
        return out;
    }
}
