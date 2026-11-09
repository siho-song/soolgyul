/// Korean display names for the places a catalog product comes from.
///
/// The catalog stores an ISO country code and the Korean name of the product's
/// region row ('꼬뜨 드 뉘'; older saved cards may carry the path form
/// '부르고뉴(Bourgogne) > 꼬뜨 드 뉘(Côte de Nuits)'). These helpers turn them into
/// the short form a product card shows: '프랑스 꼬뜨 드 뉘'.
abstract final class CatalogPlaceNames {
  static const Map<String, String> _countries = <String, String>{
    'AM': '아르메니아',
    'AR': '아르헨티나',
    'AT': '오스트리아',
    'AU': '호주',
    'AZ': '아제르바이잔',
    'BB': '바베이도스',
    'BE': '벨기에',
    'BG': '불가리아',
    'BM': '버뮤다',
    'BR': '브라질',
    'BZ': '벨리즈',
    'CA': '캐나다',
    'CH': '스위스',
    'CL': '칠레',
    'CN': '중국',
    'CO': '콜롬비아',
    'CU': '쿠바',
    'CZ': '체코',
    'DE': '독일',
    'DK': '덴마크',
    'DO': '도미니카공화국',
    'EE': '에스토니아',
    'EG': '이집트',
    'ES': '스페인',
    'FI': '핀란드',
    'FJ': '피지',
    'FR': '프랑스',
    'GB': '영국',
    'GE': '조지아',
    'GR': '그리스',
    'GT': '과테말라',
    'GY': '가이아나',
    'HR': '크로아티아',
    'HT': '아이티',
    'HU': '헝가리',
    'ID': '인도네시아',
    'IE': '아일랜드',
    'IL': '이스라엘',
    'IN': '인도',
    'IS': '아이슬란드',
    'IT': '이탈리아',
    'JM': '자메이카',
    'JO': '요르단',
    'JP': '일본',
    'KH': '캄보디아',
    'KR': '한국',
    'LA': '라오스',
    'LB': '레바논',
    'LK': '스리랑카',
    'LT': '리투아니아',
    'LV': '라트비아',
    'MA': '모로코',
    'MD': '몰도바',
    'ME': '몬테네그로',
    'MM': '미얀마',
    'MN': '몽골',
    'MU': '모리셔스',
    'MX': '멕시코',
    'NI': '니카라과',
    'NL': '네덜란드',
    'NO': '노르웨이',
    'NP': '네팔',
    'NZ': '뉴질랜드',
    'PA': '파나마',
    'PE': '페루',
    'PH': '필리핀',
    'PL': '폴란드',
    'PR': '푸에르토리코',
    'PT': '포르투갈',
    'RO': '루마니아',
    'RS': '세르비아',
    'RU': '러시아',
    'SC': '세이셸',
    'SE': '스웨덴',
    'SG': '싱가포르',
    'SI': '슬로베니아',
    'SK': '슬로바키아',
    'SV': '엘살바도르',
    'TH': '태국',
    'TR': '튀르키예',
    'TT': '트리니다드토바고',
    'TW': '대만',
    'UA': '우크라이나',
    'US': '미국',
    'UY': '우루과이',
    'UZ': '우즈베키스탄',
    'VE': '베네수엘라',
    'VI': '미국령 버진아일랜드',
    'VN': '베트남',
    'ZA': '남아프리카공화국',
  };

  /// '프랑스' for 'FR'; an unknown code is shown as it is.
  static String? country(String? code) {
    if (code == null || code.isEmpty) return null;
    return _countries[code.toUpperCase()] ?? code;
  }

  /// The most specific region without its romanisation:
  /// '부르고뉴(Bourgogne) > 꼬뜨 드 뉘(Côte de Nuits)' becomes '꼬뜨 드 뉘'.
  static String? region(String? path) {
    if (path == null) return null;
    final last = path.split('>').last;
    final korean = last.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();
    return korean.isEmpty ? null : korean;
  }

  /// '프랑스 꼬뜨 드 뉘', or whichever half is known.
  static String? place({String? countryCode, String? regionPath}) {
    final parts = <String>[?country(countryCode), ?region(regionPath)];
    return parts.isEmpty ? null : parts.join(' ');
  }
}
