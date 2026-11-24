enum __attribute__((packed)) PE8 { PE8a = 1, PE8b = 2 };
enum __attribute__((packed)) PE16 { PE16a = 300 };
struct HoldsPacked { PE8 e; PE16 f; };
