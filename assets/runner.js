// src/runner.ts
async function runDemo(bundle) {
  console.log("[Runner] TypeScript entry point launched.");
  const container = document.createElement("div");
  container.id = "demo-vfs-inspector";
  container.style.cssText = `
    position: fixed; inset: 0; background: #0c0d12; color: #d1d5db;
    font-family: ui-monospace, Menlo, Monaco, Consolas, monospace;
    font-size: 13px; padding: 32px; overflow-y: auto; z-index: 10000;
  `;
  const files = bundle.listFiles();
  let fetchTestStatus = "Testing...";
  try {
    const testFile = files.find((f) => f.path.endsWith(".glsl") || f.path.endsWith(".json")) || files[0];
    if (testFile) {
      const testResp = await fetch(`assets/${testFile.path}`);
      const isVirtual = testResp.headers.get("X-Virtual-Asset") === "true";
      fetchTestStatus = isVirtual ? `\u{1F7E2} fetch('assets/${testFile.path}') intercepted via VFS (Status: ${testResp.status})` : `\u{1F534} Native fetch reached`;
    } else {
      fetchTestStatus = "\u{1F7E1} No assets to test fetch against";
    }
  } catch (err) {
    fetchTestStatus = `\u{1F534} Error: ${err.message}`;
  }
  container.innerHTML = `
    <div style="max-width: 960px; margin: 0 auto;">
      <div style="display:flex; justify-content:space-between; align-items:center; border-bottom: 1px solid #27272a; padding-bottom: 16px; margin-bottom: 24px;">
        <h1 style="color: #60a5fa; margin: 0; font-size: 1.4rem; letter-spacing: -0.02em;">
          DEMO RUNNER // VFS INSPECTOR
        </h1>
        <span style="background: #1e293b; color: #94a3b8; padding: 4px 10px; border-radius: 9999px; font-size: 11px;">
          Created: ${new Date(bundle.meta.created).toLocaleTimeString()}
        </span>
      </div>

      <div style="background: #18181b; border: 1px solid #27272a; padding: 12px 16px; border-radius: 6px; margin-bottom: 20px;">
        <div><strong>VFS Fetch Status:</strong> ${fetchTestStatus}</div>
        <div style="margin-top: 4px; color: #9ca3af;">Total Assets Packed: <strong>${files.length}</strong></div>
      </div>

      <table style="width: 100%; border-collapse: collapse; text-align: left;">
        <thead>
          <tr style="border-bottom: 1px solid #3f3f46; color: #9ca3af;">
            <th style="padding: 8px;">File Path</th>
            <th style="padding: 8px;">MIME Type</th>
            <th style="padding: 8px;">Packed Size</th>
            <th style="padding: 8px;">Compressed</th>
            <th style="padding: 8px;">Action</th>
          </tr>
        </thead>
        <tbody>
          ${files.map((f) => `
            <tr style="border-bottom: 1px solid #27272a;">
              <td style="padding: 10px 8px; color: #f3f4f6; font-weight: 500;">${f.path}</td>
              <td style="padding: 10px 8px; color: #94a3b8;">${f.mime}</td>
              <td style="padding: 10px 8px;">${(f.size / 1024).toFixed(1)} KB</td>
              <td style="padding: 10px 8px;">${f.compressed ? "\u26A1 Deflate" : "\u2014"}</td>
              <td style="padding: 10px 8px;">
                <button data-file="${f.path}" class="preview-btn" style="
                  background: #2563eb; color: #fff; border: 0; padding: 4px 10px;
                  border-radius: 4px; cursor: pointer; font-size: 11px;
                ">Inspect</button>
              </td>
            </tr>
          `).join("")}
        </tbody>
      </table>

      <div id="preview-box" style="margin-top: 24px; padding: 16px; background: #000; border: 1px solid #3f3f46; border-radius: 6px; display: none;">
        <h4 id="preview-title" style="margin: 0 0 10px 0; color: #38bdf8;"></h4>
        <div id="preview-content"></div>
      </div>
    </div>
  `;
  document.body.appendChild(container);
  const buttons = container.querySelectorAll(".preview-btn");
  buttons.forEach((btn) => {
    btn.addEventListener("click", async (e) => {
      const target = e.target;
      const filePath = target.getAttribute("data-file");
      if (!filePath) return;
      const box = document.getElementById("preview-box");
      const title = document.getElementById("preview-title");
      const content = document.getElementById("preview-content");
      box.style.display = "block";
      title.innerText = `Previewing: ${filePath}`;
      content.innerHTML = '<span style="color:#6b7280;">Loading asset...</span>';
      const asset = await bundle.get(filePath);
      if (asset.mime.startsWith("image/")) {
        content.innerHTML = `<img src="${asset.url}" style="max-width: 100%; max-height: 400px; border: 1px solid #333;" />`;
      } else if (asset.mime.startsWith("audio/")) {
        content.innerHTML = `<audio controls src="${asset.url}" autoplay style="width: 100%;"></audio>`;
      } else if (asset.mime.startsWith("text/") || filePath.match(/\.(glsl|js|json|vert|frag)$/)) {
        const text = asset.text();
        content.innerHTML = `<pre style="max-height: 300px; overflow: auto; background: #111; padding: 12px; color: #a5f3fc; border-radius: 4px;"><code>${text.replace(/</g, "&lt;")}</code></pre>`;
      } else {
        content.innerHTML = `<div>Binary Blob ready: <strong>${asset.bytes.byteLength} bytes</strong></div><a href="${asset.url}" download="${filePath}" style="color: #60a5fa; text-decoration: underline;">Download Blob</a>`;
      }
    });
  });
}
export {
  runDemo
};
