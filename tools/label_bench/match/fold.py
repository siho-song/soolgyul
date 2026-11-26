"""Text as the label match compares it, the same in the database
(soolgyul_label_fold) and the app (labelMatchFold): compatibility
decomposition, marks off, lower case, apostrophes dropped, anything but
letters and digits one space."""
import re, unicodedata

KEEP = re.compile(r'[^0-9a-z぀-ヿ㐀-鿿가-힣]+')
YEAR = re.compile(r'\s+(?:19|20)\d\d$')


def fold(s):
    s = unicodedata.normalize('NFKD', s or '')
    s = unicodedata.normalize('NFC', ''.join(c for c in s if not unicodedata.combining(c))).lower()
    s = s.replace('’', "'").replace("'", '')
    return KEEP.sub(' ', s).strip()


def words(s):
    return fold(s).split()


def drink_of(name):
    """A drink's name as one drink: its years are the same drink."""
    return YEAR.sub('', (name or '').strip())


def line_finds(unit):
    """What the line search found for a unit, as the app has it: a bottle
    cut out of a photo of several is not line-searched."""
    return [] if unit['set'] == 'cut' else unit.get('app', [])
