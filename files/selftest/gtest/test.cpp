#include <gtest/gtest.h>

#include <array>
#include <numeric>

TEST(SelfTest, Accumulate)
{
    const std::array<int, 4> values{1, 2, 3, 4};
    EXPECT_EQ(std::accumulate(values.begin(), values.end(), 0), 10);
}
