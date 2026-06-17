// daily_rate calculates the daily rate given an hourly rate
double daily_rate(double hourly_rate) {
    return hourly_rate * 8.0;
}

// apply_discount calculates the price after a discount
double apply_discount(double before_discount, double discount) {
    return before_discount * (1.0 - discount / 100.0);
}

// monthly_rate calculates the monthly rate, given an hourly rate and a discount
// The returned monthly rate is rounded up to the nearest integer.
int monthly_rate(double hourly_rate, double discount) {
    double r_d = apply_discount(daily_rate(hourly_rate)*22.0, discount);
    int r = (int)r_d;
    if (r_d - r > 0) {
        r++;
    }
    return r;
}

// days_in_budget calculates the number of workdays given a budget, hourly rate,
// and discount The returned number of days is rounded down (take the floor) to
// the next integer.
int days_in_budget(int budget, double hourly_rate, double discount) {
    double discounted_rate = apply_discount(daily_rate(hourly_rate), discount);
    double days = budget / discounted_rate;
    int int_days = (int) days;
    return int_days;
}
