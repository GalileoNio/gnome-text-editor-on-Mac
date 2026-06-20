const appGrid = document.querySelector("[data-app-grid]");
const directoryLists = document.querySelectorAll("[data-app-list]");
const appDetail = document.querySelector("[data-app-detail]");
const appCount = document.querySelector("[data-count-apps]");
const appsJsonPath = document.body?.dataset.appsJson || "apps.json";
const assetBase = document.body?.dataset.assetBase || "";

const statusClasses = {
  Running: "ready",
  Packaging: "packaging",
  Research: "research",
};

function text(value, fallback = "") {
  return typeof value === "string" && value.trim() ? value : fallback;
}

function withBase(value) {
  if (!value || /^(https?:|mailto:|#|\/)/.test(value)) {
    return value;
  }

  return `${assetBase}${value}`;
}

function createChipList(items) {
  const list = document.createElement("ul");
  list.className = "chip-list";

  items.forEach((item) => {
    const chip = document.createElement("li");
    chip.textContent = item;
    list.append(chip);
  });

  return list;
}

function createMeta(label, value) {
  const item = document.createElement("div");
  const term = document.createElement("dt");
  const detail = document.createElement("dd");

  term.textContent = label;
  detail.textContent = value;
  item.append(term, detail);

  return item;
}

function renderApp(app, options = {}) {
  const card = document.createElement(options.linkCard ? "a" : "article");
  card.className = options.linkCard ? "app-card app-card-link" : "app-card";

  if (options.linkCard) {
    card.href = withBase(text(app.detailPath, `apps/${app.slug || ""}/`));
    card.setAttribute("aria-label", `查看 ${text(app.name, "GNOME app")} 详情`);
  }

  const header = document.createElement("div");
  header.className = "app-card-header";

  const icon = document.createElement("img");
  icon.className = "app-icon";
  icon.src = withBase(text(app.icon, "assets/icons/org.gnome.TextEditor.svg"));
  icon.alt = `${text(app.name, "GNOME app")} 图标`;
  icon.width = 58;
  icon.height = 58;

  const titleWrap = document.createElement("div");
  const title = document.createElement("h3");
  const appId = document.createElement("p");

  title.textContent = text(app.name, "Unnamed app");
  appId.className = "app-id";
  appId.textContent = text(app.id, "org.gnome.App");
  titleWrap.append(title, appId);
  header.append(icon, titleWrap);

  const status = document.createElement("p");
  const statusValue = text(app.status, "Research");
  status.className = `status-pill ${statusClasses[statusValue] || "research"}`;
  status.textContent = statusValue;

  const summary = document.createElement("p");
  summary.className = "summary";
  summary.textContent = text(app.summary, "这个应用正在移植记录中。");

  card.append(header, status, summary);

  if (app.screenshot) {
    const shot = document.createElement("div");
    const image = document.createElement("img");
    shot.className = "app-shot";
    image.src = withBase(app.screenshot);
    image.alt = `${text(app.name, "GNOME app")} 界面截图`;
    image.loading = "lazy";
    shot.append(image);
    card.append(shot);
  }

  if (Array.isArray(app.toolkit) && app.toolkit.length) {
    card.append(createChipList(app.toolkit));
  }

  const meta = document.createElement("dl");
  meta.className = "app-meta";
  meta.append(
    createMeta("Version", text(app.version, "TBD")),
    createMeta("Target", text(app.macTarget, "macOS"))
  );
  card.append(meta);

  if (options.linkCard) {
    const footer = document.createElement("span");
    footer.className = "app-card-footer";
    footer.textContent = "查看详情";
    card.append(footer);
  }

  return card;
}

function renderAppCollection(container, apps, emptyText, options = {}) {
  container.replaceChildren();

  if (!apps.length) {
    const empty = document.createElement("p");
    empty.className = "empty-state";
    empty.textContent = emptyText;
    container.append(empty);
    return;
  }

  apps.forEach((app) => container.append(renderApp(app, options)));
}

function renderApps(apps) {
  if (appGrid) {
    renderAppCollection(
      appGrid,
      apps,
      "还没有应用条目。把第一个移植成果写进 site/apps.json 就会显示在这里。",
      { linkCard: true }
    );
  }

  if (appCount) {
    appCount.textContent = String(apps.length);
  }
}

function appBelongsToGroup(app, group) {
  return Array.isArray(app.groups) && app.groups.includes(group);
}

function renderDirectory(apps) {
  directoryLists.forEach((container) => {
    const group = container.dataset.appList;
    const emptyText =
      container.dataset.emptyText ||
      "这个分类暂时还没有条目，新的移植应用会显示在这里。";
    const filtered = apps.filter((app) => appBelongsToGroup(app, group));
    renderAppCollection(container, filtered, emptyText, { linkCard: true });
  });
}

function createActionLink(action) {
  const link = document.createElement("a");
  link.className = "button secondary";
  link.href = withBase(action.href);
  link.textContent = text(action.label, "打开链接");

  if (/^https?:/.test(action.href)) {
    link.rel = "noreferrer";
  }

  return link;
}

function renderDetail(apps) {
  if (!appDetail) {
    return;
  }

  const slug = appDetail.dataset.appDetail;
  const app = apps.find((item) => item.slug === slug);

  appDetail.replaceChildren();

  if (!app) {
    const empty = document.createElement("p");
    empty.className = "empty-state";
    empty.textContent = "没有找到这个应用条目。请检查详情页的 slug 是否和 site/apps.json 一致。";
    appDetail.append(empty);
    return;
  }

  document.title = `${app.name} - GNOME on Mac`;

  const back = document.createElement("a");
  back.className = "back-link";
  back.href = withBase("apps.html#circle");
  back.textContent = "返回应用列表";

  const hero = document.createElement("section");
  hero.className = "detail-hero";

  const icon = document.createElement("img");
  icon.className = "detail-icon";
  icon.src = withBase(text(app.icon, "assets/icons/org.gnome.TextEditor.svg"));
  icon.alt = `${text(app.name, "GNOME app")} 图标`;
  icon.width = 128;
  icon.height = 128;

  const copy = document.createElement("div");
  const status = document.createElement("p");
  const statusValue = text(app.status, "Research");
  const title = document.createElement("h1");
  const subtitle = document.createElement("h2");
  const description = document.createElement("p");

  status.className = `status-pill ${statusClasses[statusValue] || "research"}`;
  status.textContent = statusValue;
  title.textContent = text(app.name, "Unnamed app");
  subtitle.textContent = text(app.subtitle, app.id);
  description.className = "detail-description";
  description.textContent = text(app.description, app.summary);
  copy.append(status, title, subtitle, description);

  if (Array.isArray(app.actions) && app.actions.length) {
    const actions = document.createElement("div");
    actions.className = "detail-actions";
    app.actions.forEach((action) => actions.append(createActionLink(action)));
    copy.append(actions);
  }

  hero.append(icon, copy);

  const screenshots = document.createElement("section");
  screenshots.className = "detail-section";
  screenshots.innerHTML = "<h2>预览界面</h2>";
  const shotGrid = document.createElement("div");
  shotGrid.className = "screenshot-grid";
  const shots = Array.isArray(app.screenshots) && app.screenshots.length
    ? app.screenshots
    : [{ src: app.screenshot, alt: `${app.name} screenshot`, caption: "应用截图" }];

  shots.filter((shot) => shot.src).forEach((shot) => {
    const figure = document.createElement("figure");
    const image = document.createElement("img");
    const caption = document.createElement("figcaption");
    image.src = withBase(shot.src);
    image.alt = text(shot.alt, `${app.name} 界面截图`);
    image.loading = "lazy";
    caption.textContent = text(shot.caption, "应用截图");
    figure.append(image, caption);
    shotGrid.append(figure);
  });
  screenshots.append(shotGrid);

  const info = document.createElement("section");
  info.className = "detail-section detail-info-grid";
  info.append(createInfoPanel("移植信息", [
    ["Bundle", text(app.bundlePath, "TBD")],
    ["Target", text(app.macTarget, "macOS")],
    ["Version", text(app.version, "TBD")],
    ["Upstream", text(app.upstreamCategory, "GNOME")]
  ]));
  info.append(createListPanel("移植备注", app.portingNotes || []));
  info.append(createListPanel("技术栈", app.toolkit || []));
  info.append(createListPanel("关键词", app.keywords || []));

  appDetail.append(back, hero, screenshots, info);
}

function createInfoPanel(title, rows) {
  const panel = document.createElement("article");
  const heading = document.createElement("h2");
  const list = document.createElement("dl");
  heading.textContent = title;
  list.className = "info-list";

  rows.forEach(([label, value]) => {
    list.append(createMeta(label, value));
  });

  panel.append(heading, list);
  return panel;
}

function createListPanel(title, items) {
  const panel = document.createElement("article");
  const heading = document.createElement("h2");
  const list = document.createElement("ul");
  heading.textContent = title;
  list.className = "detail-list";

  if (!items.length) {
    const item = document.createElement("li");
    item.textContent = "暂未记录。";
    list.append(item);
  } else {
    items.forEach((value) => {
      const item = document.createElement("li");
      item.textContent = value;
      list.append(item);
    });
  }

  panel.append(heading, list);
  return panel;
}

async function loadApps() {
  try {
    const response = await fetch(appsJsonPath, { cache: "no-store" });

    if (!response.ok) {
      throw new Error(`Unable to load apps.json: ${response.status}`);
    }

    const payload = await response.json();
    const apps = Array.isArray(payload.apps) ? payload.apps : [];
    renderApps(apps);
    renderDirectory(apps);
    renderDetail(apps);
  } catch (error) {
    console.error(error);
    const message =
      '<p class="empty-state">应用清单暂时无法读取。请通过本地 HTTP server 预览，或检查 site/apps.json。</p>';

    if (appGrid) {
      appGrid.innerHTML = message;
    }

    directoryLists.forEach((container) => {
      container.innerHTML = message;
    });

    if (appDetail) {
      appDetail.innerHTML = message;
    }
  }
}

if (appGrid || directoryLists.length || appDetail) {
  loadApps();
}
