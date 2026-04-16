class AppConstants {
  // Default Manufacturer Key for unprogrammed locks
  static final List<int> defaultManufacturerKey = [
    0x00,
    0x11,
    0x22,
    0x33,
    0x44,
    0x55,
    0x66,
    0x77,
    0x88,
    0x99,
    0xAA,
    0xBB,
    0xCC,
    0xDD,
    0xEE,
    0xFF,
  ];

  // Factory default Mifare Key A
  static final List<int> factoryKeyA = [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF];

  // Fixed Access Bits for sector trailer
  static final List<int> accessBits = [0xFF, 0x07, 0x80, 0x69];

  // Sector numbers used
  static const int sector1 = 1;
  static const int sector2 = 2;

  // Block addresses
  static const int sector1BlockStart = 4;
  static const int sector2BlockStart = 8;
  static const int trailerBlockS1 = 7;
  static const int trailerBlockS2 = 11;
}
