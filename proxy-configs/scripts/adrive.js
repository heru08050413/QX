// =====================================================================
// adrive.js — 阿里云盘:去广告/净化
// 【镜像自】 https://raw.githubusercontent.com/fmz200/wool_scripts/main/Scripts/adrive/adrive.js
//   作者 @fmz200 (fmz200/wool_scripts)   取回日期 2026-07-06
// 【为何镜像】 去第三方 raw 死链风险(Stash 报 Scripts Not Downloaded);
//   镜像进本仓库后 script-providers 只引自己链接。未改动上游逻辑。
// =====================================================================
// 2024-07-15 21:30

const url = $request.url;
if (!$response.body) $done({});
let obj = JSON.parse($response.body);

if (url.includes("/v1/users/onboard_list")) {
  if (obj.result?.length > 0) {
    obj.result = obj.result.filter(
      (i) =>
        ![
          "backup_list_under_mydevice_banner",
          "backup_top_banner",
          "home_bulletin_board",
          "home_top_banner",
          "resource_top_banner",
          "video_top_banner"
        ]?.includes(i?.anchor)
    );
  }
} else if (url.includes("/v2/users/home/news")) {
  if (obj.result?.length > 0) {
    obj.result = obj.result.filter((i) => !i?.code?.includes("productUpdate"));
  }
} else if (url.includes("/v1/user/home/widgets") || url.includes("/v2/users/home/widgets")) {
  const item = [
    "album", // 相册
    "banners", // 顶部奖励
    "coreFeatures", // 横版图标
    "introduceAlipan", // 认识阿里云盘
    "mainBackup", // 手机备份
    "minorBackup", // 备份设备列表
    "signIn" // 签到
  ];
  item.forEach((i) => {
    delete obj[i];
  });
}

$done({ body: JSON.stringify(obj) });
