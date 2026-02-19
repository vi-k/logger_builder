/// Logging levels.
///
/// These are not absolute values, but simply constants for convenience. You
/// can use them or set your own.
///
/// Leave only the extreme values untouched: [all] and [off]. Let your values
/// be in between them.
abstract final class Levels {
  static const int all = 0;

  static const int finest = 300;
  static const int finer = 400;
  static const int fine = 500;
  static const int config = 700;
  static const int info = 800;
  static const int warning = 900;
  static const int severe = 1000;
  static const int shout = 1200;

  static const int trace = finest;
  static const int verbose = finer;
  static const int debug = fine;
  static const int error = severe;
  static const int critical = shout;

  static const int off = 2000;
}
