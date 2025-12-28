# Sample questions

"
How does the month of the year affect the expected number of flight delays per airport?

Do some carriers have systematically more delays than others, after controlling for airport 
and month?”

Does day-of-week influence the expected count of delays?
"

"
What is our Y?

The number of delayed flights (>15 minutes) per airport per month

"
rm(list = ls())

library(tidyverse)
library(caret)
library(dplyr)
library(MASS)

setwd("~/Desktop/Projects/R Projects/Flight_delays_poisson_regression/CSV_files")
list.files()

# Loading the data

flights <- read_csv("flight_delay.csv", show_col_types = FALSE)

glimpse(flights)
summary(flights)

# Cleaning the data

flights_clean <- flights %>%
  mutate(
    month = as.factor(month),
    airport = as.factor(airport),
    carrier = as.factor(carrier)
  ) %>%
  drop_na(arr_del15, arr_flights, month, airport, carrier) %>%
  mutate(month = factor(month, levels = 1:12, labels = month.abb)) %>%
  filter(arr_flights >= 30)

flights_clean <- flights_clean %>%
  mutate(
    carrier = forcats::fct_relevel(carrier, "DL"),
    airport = forcats::fct_relevel(airport, "ATL"),
    month = forcats::fct_relevel(month, "Jan")
  )

carrier_lookup <- NULL

if ("carrier_name" %in% names(flights_clean)) {
  carrier_lookup <- flights_clean %>%
    dplyr::filter(!is.na(carrier_name)) %>%
    dplyr::count(carrier, carrier_name, sort = TRUE) %>%
    dplyr::group_by(carrier) %>%
    dplyr::slice_head(n = 1) %>%
    dplyr::ungroup() %>%
    dplyr::select(carrier, carrier_name)
}

# Train / Test split

set.seed(42)
idx <- createDataPartition(flights_clean$arr_del15, p = 0.80, list = FALSE)

train <- flights_clean[idx, ]
test <- flights_clean[-idx, ]


# Negative Binomial

nb1 <- glm.nb(
  arr_del15 ~ month + airport + carrier + offset(log(arr_flights)),
  data = train
)

# Extracting and ranking effects of airports and carriers

coef_tbl <- as.data.frame(summary(nb1)$coefficients) %>%
  rownames_to_column("term") %>%
  rename(
    estimate = Estimate,
    std_error = 'Std. Error',
    z_value = 'z value',
    p_value = 'Pr(>|z|)'
  ) %>%
  mutate(
    rate_ratio = exp(estimate),
    rr_low_95 = exp(estimate - 1.96 * std_error),
    rr_high_95 = exp(estimate + 1.96 * std_error)
  )

airport_effects <- coef_tbl %>%
  dplyr::filter(stringr::str_starts(term, "airport")) %>%
  dplyr::mutate(airport = stringr::str_remove(term, "^airport")) %>%
  dplyr::select(airport, rate_ratio, rr_low_95, rr_high_95, estimate, std_error, z_value, p_value) %>%
  dplyr::arrange(dplyr::desc(rate_ratio))


airport_worst_10 <- airport_effects %>% slice_head(n = 10)
airport_best_10 <- airport_effects %>% slice_tail(n = 10)

cat("\n================\nTOP 10 WORST AIRPORTS (highest adjusted delay rate)\n================\n")
print(airport_worst_10)

cat("\n================\nTOP 10 BEST AIRPORTS (lowest adjusted delay rate)\n================\n")
print(airport_best_10)

carrier_effects <- coef_tbl %>%
  dplyr::filter(stringr::str_starts(term, "carrier")) %>%
  dplyr::mutate(carrier = stringr::str_remove(term, "^carrier")) %>%
  dplyr::select(carrier, rate_ratio, rr_low_95, rr_high_95, estimate, std_error, z_value, p_value) %>%
  dplyr::arrange(dplyr::desc(rate_ratio))

baseline_carrier <- tibble::tibble(
  carrier = "DL",
  rate_ratio = 1,
  rr_low_95 = 1,
  rr_high_95 = 1,
  estimate = 0,
  std_error = NA_real_,
  z_value = NA_real_,
  p_value = NA_real_
)

baseline_carrier <- baseline_carrier %>%
  mutate(carrier_name = "Delta Airlines")

if(!is.null(carrier_lookup)) {
  carrier_effects <- carrier_effects %>%
    dplyr::left_join(carrier_lookup, by = "carrier") %>%
    dplyr::relocate(carrier_name, .after = carrier)
}

carrier_effects_all <- dplyr::bind_rows(carrier_effects, baseline_carrier)

carrier_worst_10 <- carrier_effects_all %>% 
  dplyr::arrange(dplyr::desc(rate_ratio)) %>%
  dplyr::slice_head(n = 10)


carrier_best_10  <- carrier_effects_all %>% 
  dplyr::arrange(rate_ratio) %>%
  dplyr::slice_head(n = 10)

cat("\n================\nTOP 10 WORST CARRIERS (highest adjusted delay rate)\n================\n")
print(carrier_worst_10)

cat("\n================\nTOP 10 BEST CARRIERS (lowest adjusted delay rate)\n================\n")
print(carrier_best_10)


# Plots for worst airports and carriers

ggplot(airport_worst_10, aes(x = reorder(airport, rate_ratio), y = rate_ratio)) +
  geom_col() +
  coord_flip() +
  labs(
    title = "Top 10 Airports with Highest Adjusted Delay Rate",
    x = "Airport",
    y = "Rate Ratio (RR)"
  )

plot_carrier_df <- carrier_worst_10
carrier_label_col <- if("carrier_name" %in% names(plot_carrier_df)) "carrier_name" else "carrier"

ggplot(plot_carrier_df, aes(x = reorder(.data[[carrier_label_col]], rate_ratio), y = rate_ratio)) +
  geom_col() +
  coord_flip() +
  labs(
    title = "Top 10 Carriers with Highest Adjusted Delay Rate",
    x = "Carrier",
    y = "Rate Ratio (RR)"
  )

"\n

A Negative Binomial regression model was fitted to monthly airport-level counts of delayed arrivals, using 
the log of total arrivals as an offset. After controlling for month and airport effects, substantial 
heterogeneity was observed across carriers. For example, Frontier Airlines exhibited an adjusted delay rate 
approximately 77% higher than Delta Air Lines, while Endeavor Air exhibited a delay rate approximately 3% 
lower.

Significant airport-level differences were also observed: several small regional airports exhibited delay 
rates less than half that of the baseline airport (ATL), while others exhibited rates nearly double.

\n"







