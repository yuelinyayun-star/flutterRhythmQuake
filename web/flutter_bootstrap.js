{{flutter_js}}
{{flutter_build_config}}

(async () => {
  const startup = window.rqStartup;
  const total = Number(document.querySelector('meta[name="rhythmquake-main-js-bytes"]')?.content);
  const build = _flutter.buildConfig.builds.find((item) => item.compileTarget === 'dart2js');

  // The deployed build has an exact, version-matched byte count. Reading the
  // response stream reports real download progress, including gzip responses.
  // Flutter then loads the same URL from the browser cache.
  if (build && Number.isSafeInteger(total) && total > 0) {
    try {
      startup?.stage('正在下载主程序…');
      startup?.download(0, total);
      const response = await fetch(new URL(build.mainJsPath, document.baseURI));
      if (!response.ok) throw new Error(`Main script HTTP ${response.status}`);
      if (response.body) {
        const reader = response.body.getReader();
        let loaded = 0;
        while (true) {
          const {done, value} = await reader.read();
          if (done) break;
          loaded += value.byteLength;
          startup?.download(loaded, total);
        }
      } else {
        await response.arrayBuffer();
      }
      startup?.download(total, total);
    } catch (error) {
      console.error('RhythmQuake main script download failed', error);
      startup?.fail();
      return;
    }
  }

  const config = {canvasKitBaseUrl: 'canvaskit/'};
  try {
    await _flutter.loader.load({
      config,
      serviceWorkerSettings: {
        serviceWorkerVersion: {{flutter_service_worker_version}},
      },
      onEntrypointLoaded: async (engineInitializer) => {
        try {
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
