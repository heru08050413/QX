// =====================================================================
// dict-youdao-ad.js — 有道词典:去广告
// 【镜像自】 https://raw.githubusercontent.com/fmz200/wool_scripts/main/Scripts/youdao/dict-youdao-ad.js
//   作者 @fmz200 (fmz200/wool_scripts)   取回日期 2026-07-06
// 【为何镜像】 去第三方 raw 死链风险(Stash 报 Scripts Not Downloaded);
//   镜像进本仓库后 script-providers 只引自己链接。未改动上游逻辑。
// =====================================================================
/*************************************

 项目名称：网易有道词典-首页净化，学习Tab界面净化，首页听读训练净化
 使用声明：⚠️仅供参考，🈲转载与售卖！

 **************************************

 [rewrite_local]
^https:\/\/dict\.youdao\.com\/(homepage\/promotion|course\/tab\/home|homepage\/tile) url script-response-body https://raw.githubusercontent.com/fmz200/wool_scripts/main/Scripts/youdao/dict-youdao-ad.js

 [mitm]
 hostname = dict.youdao.com
 ************************************/

let obj = JSON.parse($response.body);
const url = $request.url;

if (url.includes('/homepage/promotion')) {
  obj.data.dataList = obj.data.dataList.filter(i => i.type === 'WOW');
} else if (url.includes('/course/tab/home')) {
  obj.data.tab.tabList = obj.data.tab.tabList.filter(i => i.title === '学库' || i.title === '四六级');
  obj.data.icon.iconList = obj.data.icon.iconList.filter(i => i.title === '实用英语');
  obj.data.fragmentList = obj.data.fragmentList.filter(i => i.type === 'GREAT_COURSE');
} else if (url.includes('/homepage/tile')) {
  obj.data.children = obj.data.children.filter(i => i.type === '');
}

$done({body: JSON.stringify(obj)});
