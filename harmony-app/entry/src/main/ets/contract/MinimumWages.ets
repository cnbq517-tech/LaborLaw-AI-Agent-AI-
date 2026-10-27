// Monthly minimum wages for full-time work, by province, from the table at
// https://m12333.cn/policy/wrib.html (published 2026-09-16; not an official
// site). Only the provincial tiers are public there: which tier a city or
// county uses is in each province's attachment, so a wage between a
// province's lowest and highest tier is left for the user to check.
//
// Update the table, MINIMUM_WAGE_SOURCE and MINIMUM_WAGE_AS_OF together.

export const MINIMUM_WAGE_SOURCE: string = 'm12333.cn 整理的各省最低工资标准';
export const MINIMUM_WAGE_AS_OF: string = '2026-09-16';

export class ProvinceWage {
  province: string;
  effective: string;
  // Tiers from highest to lowest, yuan per month.
  tiers: number[];

  constructor(province: string, effective: string, tiers: number[]) {
    this.province = province;
    this.effective = effective;
    this.tiers = tiers;
  }

  highest(): number {
    return this.tiers[0];
  }

  lowest(): number {
    return this.tiers[this.tiers.length - 1];
  }
}

// 广东 lists two first-tier figures (2680 and 2700); the higher one is used,
// which only widens the range that asks the user to check.
const WAGES: ProvinceWage[] = [
  new ProvinceWage('北京', '2025-09-01', [2540]),
  new ProvinceWage('天津', '2025-09-01', [2510]),
  new ProvinceWage('河北', '2025-12-01', [2380, 2230, 2080]),
  new ProvinceWage('山西', '2026-10-01', [2350, 2250, 2150]),
  new ProvinceWage('内蒙古', '2025-12-01', [2380, 2310, 2250]),
  new ProvinceWage('辽宁', '2025-12-01', [2230, 2080, 1930]),
  new ProvinceWage('吉林', '2025-12-01', [2230, 2020, 1870]),
  new ProvinceWage('黑龙江', '2025-12-01', [2270, 2010, 1910]),
  new ProvinceWage('上海', '2025-07-01', [2740]),
  new ProvinceWage('江苏', '2026-01-01', [2660, 2430, 2180]),
  new ProvinceWage('浙江', '2026-01-01', [2660, 2430, 2180]),
  new ProvinceWage('安徽', '2025-09-01', [2320, 2170, 2100, 2000]),
  new ProvinceWage('福建', '2025-04-01', [2265, 2195, 2045, 1895]),
  new ProvinceWage('江西', '2025-12-01', [2240, 2090, 1950]),
  new ProvinceWage('山东', '2025-10-01', [2400, 2210, 2020]),
  new ProvinceWage('河南', '2025-12-01', [2350, 2150, 2000]),
  new ProvinceWage('湖北', '2025-12-01', [2400, 2130, 1970]),
  new ProvinceWage('湖南', '2025-09-01', [2200, 2000, 1800]),
  new ProvinceWage('广东', '2026-09-01', [2700, 2300, 2040]),
  new ProvinceWage('广西', '2025-07-01', [2200, 2040, 1870]),
  new ProvinceWage('海南', '2025-12-01', [2250, 2070]),
  new ProvinceWage('重庆', '2025-01-01', [2330, 2200]),
  new ProvinceWage('四川', '2025-01-01', [2330, 2200]),
  new ProvinceWage('贵州', '2025-02-01', [2130, 1980, 1890]),
  new ProvinceWage('云南', '2026-09-01', [2270, 2120, 1970]),
  new ProvinceWage('西藏', '2025-11-01', [2360]),
  new ProvinceWage('陕西', '2026-01-01', [2376, 2250, 2140]),
  new ProvinceWage('甘肃', '2025-12-01', [2200, 2130, 2080]),
  new ProvinceWage('青海', '2025-05-01', [2080]),
  new ProvinceWage('宁夏', '2025-10-01', [2235, 2080]),
  new ProvinceWage('新疆', '2026-10-01', [2270, 2080, 1930])
];

// Prefecture-level cities and regions, by province. A city name in the facts
// (广州, 广州市) is looked up here; province names are matched directly.
const CITIES: string[][] = [
  ['河北', '石家庄 唐山 秦皇岛 邯郸 邢台 保定 张家口 承德 沧州 廊坊 衡水 雄安'],
  ['山西', '太原 大同 阳泉 长治 晋城 朔州 晋中 运城 忻州 临汾 吕梁'],
  ['内蒙古', '呼和浩特 包头 乌海 赤峰 通辽 鄂尔多斯 呼伦贝尔 巴彦淖尔 乌兰察布 兴安 锡林郭勒 阿拉善'],
  ['辽宁', '沈阳 大连 鞍山 抚顺 本溪 丹东 锦州 营口 阜新 辽阳 盘锦 铁岭 朝阳 葫芦岛'],
  ['吉林', '长春 吉林 四平 辽源 通化 白山 松原 白城 延边'],
  ['黑龙江', '哈尔滨 齐齐哈尔 鸡西 鹤岗 双鸭山 大庆 伊春 佳木斯 七台河 牡丹江 黑河 绥化 大兴安岭'],
  ['江苏', '南京 无锡 徐州 常州 苏州 南通 连云港 淮安 盐城 扬州 镇江 泰州 宿迁 昆山 江阴 张家港 常熟'],
  ['浙江', '杭州 宁波 温州 嘉兴 湖州 绍兴 金华 衢州 舟山 台州 丽水 义乌'],
  ['安徽', '合肥 芜湖 蚌埠 淮南 马鞍山 淮北 铜陵 安庆 黄山 滁州 阜阳 宿州 六安 亳州 池州 宣城'],
  ['福建', '福州 厦门 莆田 三明 泉州 漳州 南平 龙岩 宁德 晋江'],
  ['江西', '南昌 景德镇 萍乡 九江 新余 鹰潭 赣州 吉安 宜春 抚州 上饶'],
  ['山东', '济南 青岛 淄博 枣庄 东营 烟台 潍坊 济宁 泰安 威海 日照 临沂 德州 聊城 滨州 菏泽'],
  ['河南', '郑州 开封 洛阳 平顶山 安阳 鹤壁 新乡 焦作 濮阳 许昌 漯河 三门峡 南阳 商丘 信阳 周口 驻马店 济源'],
  ['湖北', '武汉 黄石 十堰 宜昌 襄阳 鄂州 荆门 孝感 荆州 黄冈 咸宁 随州 恩施 仙桃 潜江 天门 神农架'],
  ['湖南', '长沙 株洲 湘潭 衡阳 邵阳 岳阳 常德 张家界 益阳 郴州 永州 怀化 娄底 湘西'],
  ['广东', '广州 深圳 珠海 汕头 佛山 韶关 湛江 肇庆 江门 茂名 惠州 梅州 汕尾 河源 阳江 清远 东莞 中山 潮州 揭阳 云浮'],
  ['广西', '南宁 柳州 桂林 梧州 北海 防城港 钦州 贵港 玉林 百色 贺州 河池 来宾 崇左'],
  ['海南', '海口 三亚 三沙 儋州 琼海 万宁 文昌 五指山 东方'],
  ['四川', '成都 自贡 攀枝花 泸州 德阳 绵阳 广元 遂宁 内江 乐山 南充 眉山 宜宾 广安 达州 雅安 巴中 资阳 阿坝 甘孜 凉山'],
  ['贵州', '贵阳 六盘水 遵义 安顺 毕节 铜仁 黔西南 黔东南 黔南'],
  ['云南', '昆明 曲靖 玉溪 保山 昭通 丽江 普洱 临沧 楚雄 红河 文山 西双版纳 大理 德宏 怒江 迪庆'],
  ['西藏', '拉萨 日喀则 昌都 林芝 山南 那曲 阿里'],
  ['陕西', '西安 铜川 宝鸡 咸阳 渭南 延安 汉中 榆林 安康 商洛 杨凌'],
  ['甘肃', '兰州 嘉峪关 金昌 白银 天水 武威 张掖 平凉 酒泉 庆阳 定西 陇南 临夏 甘南'],
  ['青海', '西宁 海东 海北 黄南 海南州 果洛 玉树 海西'],
  ['宁夏', '银川 石嘴山 吴忠 固原 中卫'],
  ['新疆', '乌鲁木齐 克拉玛依 吐鲁番 哈密 昌吉 博尔塔拉 巴音郭楞 阿克苏 克孜勒苏 喀什 和田 伊犁 塔城 阿勒泰 石河子']
];

export class MinimumWages {
  static all(): ProvinceWage[] {
    return WAGES;
  }

  // The province for a city or province name as the user typed it, or
  // undefined when it cannot be told.
  static forPlace(place: string): ProvinceWage | undefined {
    const name: string = place.trim();
    if (name.length === 0) {
      return undefined;
    }
    for (const wage of WAGES) {
      if (name.includes(wage.province)) {
        return wage;
      }
    }
    const city: string = name.replace(/(市|地区|自治州|州|盟)$/, '');
    for (const row of CITIES) {
      if (row[1].split(' ').some((c: string) => c === city || (c.length >= 2 && name.startsWith(c)))) {
        return WAGES.find((w: ProvinceWage) => w.province === row[0]);
      }
    }
    return undefined;
  }

  static nationalLowest(): number {
    return Math.min(...WAGES.map((w: ProvinceWage) => w.lowest()));
  }

  static nationalHighest(): number {
    return Math.max(...WAGES.map((w: ProvinceWage) => w.highest()));
  }
}
