{{flutter_js}}
{{flutter_build_config}}

(async () => {
  const startup = window.rqStartup;
  const assetBytes = (name) => Number(document.querySelector(`meta[name="${name}"]`)?.content);
  const mainBytes = assetBytes('rhythmquake-main-js-bytes');
  const build = _flutter.buildConfig.builds.find((item) => item.compileTarget === 'dart2js');

  // Response streams report decoded bytes even when Nginx serves gzip. The
  // version-matched build supplies the exact uncompressed file sizes.
  async function readAsset(path, onProgress) {
    const response = await fetch(new URL(path, document.baseURI));
    if (!response.ok) throw new Error(`${path} HTTP ${response.status}`);
    let loaded = 0;
    if (response.body) {
      const reader = response.body.getReader();
      while (true) {
        const {done, value} = await reader.read();
        if (done) break;
        loaded += value.byteLength;
        onProgress(loaded);
      }
    } else {
      loaded = (await response.arrayBuffer()).byteLength;
      onProgress(loaded);
    }
    return loaded;
  }

  // Flutter uses the same versioned main script URL from the browser cache.
  if (build && Number.isSafeInteger(mainBytes) && mainBytes > 0) {
    try {
      startup?.stage('正在下载主程序…');
      startup?.download('主程序', 0, mainBytes);
      await readAsset(build.mainJsPath, (loaded) => startup?.download('主程序', loaded, mainBytes));
      startup?.download('主程序', mainBytes, mainBytes);
    } catch (error) {
      console.error('RhythmQuake main script download failed', error);
      startup?.fail();
      return;
    }
  }

  const config = {canvasKitBaseUrl: 'canvaskit/'};
  const chromium = /(?:Edg|Chrome|Chromium|OPR)\//.test(navigator.userAgent);
  const variant = chromium ? 'chromium' : 'full';
  const engineBytes = assetBytes(`rhythmquake-canvaskit-${variant}-bytes`);
  try {
    await _flutter.loader.load({
      config,
      serviceWorkerSettings: {
        serviceWorkerVersion: {{flutter_service_worker_version}},
      },
      onEntrypointLoaded: async (engineInitializer) => {
        try {
          if (Number.isSafeInteger(engineBytes) && engineBytes > 0) {
            startup?.stage('正在下载图形引擎…');
            startup?.download('图形引擎', 0, engineBytes);
            const prefix = chromium ? 'canvaskit/chromium/' : 'canvaskit/';
            let completed = 0;
            for (const name of ['canvaskit.js', 'canvaskit.wasm']) {
              completed += await readAsset(prefix + name, (loaded) =>
                startup?.download('图形引擎', completed + loaded, engineBytes));
            }
            startup?.download('图形引擎', engineBytes, engineBytes);
          }
          startup?.stage('正在初始化图形引擎…');
          const appRunner = await engineInitializer.initializeEngine(config);
          startup?.stage('正在启动程序…');
          await appRunner.runApp();
        } catch (error) {
          console.error('RhythmQuake startup failed', error);
          startup?.fail();
        }
      },
    });
  } catch (error) {
    console.error('RhythmQuake loader failed', error);
    startup?.fail();
  }
})();
