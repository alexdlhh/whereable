#include <unity.h>
#include "../../src/battery_utils.h"

void test_empty_pack() {
    TEST_ASSERT_EQUAL(0, batteryPercentFromVoltage(3.30f));
    TEST_ASSERT_EQUAL(0, batteryPercentFromVoltage(3.00f));
}

void test_full_pack() {
    TEST_ASSERT_EQUAL(100, batteryPercentFromVoltage(4.20f));
    TEST_ASSERT_EQUAL(100, batteryPercentFromVoltage(4.35f));
}

void test_mid_pack() {
    TEST_ASSERT_EQUAL(50, batteryPercentFromVoltage(3.75f));
}

void test_adc_conversion() {
    TEST_ASSERT_FLOAT_WITHIN(0.02f, 0.0f, batteryVoltageFromAdc(0));
    TEST_ASSERT_FLOAT_WITHIN(0.05f, 6.6f, batteryVoltageFromAdc(4095));
}

int main(int argc, char **argv) {
    UNITY_BEGIN();
    RUN_TEST(test_empty_pack);
    RUN_TEST(test_full_pack);
    RUN_TEST(test_mid_pack);
    RUN_TEST(test_adc_conversion);
    return UNITY_END();
}
