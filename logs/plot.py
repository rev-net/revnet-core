import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
import numpy as np

# --- Configuration ---
CSV_FILE_PATH = 'fuzz_data.csv' # Make sure this path is correct
OUTPUT_PLOT_PATH = 'loan_cost_fuzz_plot_eth_debug.png' # Updated output filename

# Define the prepaid fee groups - Filtering for EXACT values
FEE_GROUPS = {
    '2.5% Prepaid Exact': 25,
    '25% Prepaid Exact': 250,
    '50% Prepaid Exact': 500,
}
# Color mapping
GROUP_COLORS = {
    '2.5% Prepaid Exact': 'red',
    '25% Prepaid Exact': 'green',
    '50% Prepaid Exact': 'blue',
}
# Style for "other" points
OTHER_POINTS_STYLE = {
    'color': 'grey',
    'marker': '.',
    'linestyle': 'None',
    'alpha': 0.3,
    'label': 'Other Fuzz Runs'
}

# --- Data Loading and Preparation ---
try:
    df = pd.read_csv(CSV_FILE_PATH)
    print(f"--- Data Loading ---")
    print(f"Initial shape: {df.shape}")
except FileNotFoundError:
    print(f"Error: CSV file not found at '{CSV_FILE_PATH}'")
    exit()
except Exception as e:
    print(f"Error loading CSV: {e}")
    exit()

# Prepare essential columns & Convert days to years
required_columns = ['daysUntilPaid', 'initialCapital', 'nonFeelessPaid', 'prePaidFee']
# ... (add checks for missing columns if needed) ...
df['yearsUntilPaid'] = df['daysUntilPaid'] / 365.0 # Correctly calculate years

print(f"\n--- Data Coercion & Cleaning ---")
for col in required_columns:
    df[col] = pd.to_numeric(df[col], errors='coerce')

print(f"NaN counts after coercion:\n{df.isnull().sum()}")

dropna_subset_cols = required_columns + ['yearsUntilPaid']
df.dropna(subset=dropna_subset_cols, inplace=True)
print(f"Shape after dropna: {df.shape}")

if df.empty:
    print("ERROR: DataFrame is empty after dropna.")
    exit()

# Convert types AFTER dropping NaNs. Use object for potentially huge wei values.
df['initialCapital'] = df['initialCapital'].astype(np.int64).astype(object)
df['nonFeelessPaid'] = df['nonFeelessPaid'].astype(np.int64).astype(object)
df['prePaidFee'] = df['prePaidFee'].astype(np.int64) # Keep as int for exact matching

# Calculate Total Cost (in wei)
df['totalCost_wei'] = df['nonFeelessPaid']

# Scale Cost to ETH
df['totalCost_eth'] = df['totalCost_wei'].astype(float) / 1e18

print(f"Fuzz 'totalCost_eth' calculated. Min: {df['totalCost_eth'].min()}, Max: {df['totalCost_eth'].max()}")


# --- Plotting ---
fig, ax = plt.subplots(figsize=(12, 7))

# Plot the specific groups first
processed_indices = set() # Keep track of plotted points

for group_name, exact_fee in FEE_GROUPS.items():
    # Select data for the current group using EXACT match
    group_df = df[df['prePaidFee'] == exact_fee].copy()

    print(f"\nChecking group {group_name} (prePaidFee == {exact_fee}): Found {group_df.shape[0]} points") # Moved print up

    if not group_df.empty:
        # Sort by years AND total cost to stabilize order in case of time ties
        group_df.sort_values(by=['yearsUntilPaid', 'totalCost_eth'], inplace=True) # Added secondary sort

        # --- !!! DEBUG PRINT !!! ---
        print(f"--- Data for plotting line: {group_name} (Head) ---")
        # Show relevant columns, including the source days/fees
        print(group_df[['yearsUntilPaid', 'totalCost_eth', 'daysUntilPaid', 'nonFeelessPaid', 'prePaidFee']].head())
        # --- !!! END DEBUG PRINT !!! ---

        # Plot as a line using the SCALED ETH cost
        ax.plot(
            group_df['yearsUntilPaid'],
            group_df['totalCost_eth'], # Plot ETH value
            marker='o',
            markersize=3,
            linestyle='-',
            color=GROUP_COLORS.get(group_name, 'black'),
            label=group_name
        )
        processed_indices.update(group_df.index)
    # No warning needed if empty


# Plot all *other* points as a scatter
other_df = df[~df.index.isin(processed_indices)]
print(f"\nChecking other points: Found {other_df.shape[0]} points")
if not other_df.empty:
     ax.plot(
        other_df['yearsUntilPaid'],
        other_df['totalCost_eth'], # Plot ETH value
        **OTHER_POINTS_STYLE # Apply scatter style
     )


# --- Plot Customization ---
ax.set_title('Total Loan Repayment Cost vs. Time (Fuzz Data)')
ax.set_xlabel('Years Since Loan Creation')
ax.set_ylabel('Total Cost (ETH)')

# Y-axis Formatter
formatter = mticker.FuncFormatter(lambda x, p: f'{x:.2f}')
ax.yaxis.set_major_formatter(formatter)

# Add reference line
# Convert the extracted Python int (stored as object) directly to float
initial_cap_value_eth = float(df['initialCapital'].iloc[0]) / 1e18 # Scale to ETH
ax.axhline(y=initial_cap_value_eth, color='black', linestyle='--', linewidth=0.8, label=f'Initial Capital ({initial_cap_value_eth:.2f} ETH)')


# --- Dynamic Y Limits ---
# Calculate limits based on ALL data points plotted
all_plotted_costs_eth = df['totalCost_eth'].values # Use all available points after cleaning
min_y_data = all_plotted_costs_eth.min()
max_y_data = all_plotted_costs_eth.max()
range_y = max(max_y_data - min_y_data, 1e-9) # Prevent zero range
padding_y = range_y * 0.05

# Adjust min_y calculation slightly to better ensure visibility
min_y_final = min(float(initial_cap_value_eth) * 0.95, min_y_data - padding_y)
min_y_final = max(0, min_y_final) # Don't go below zero unless data does

max_y_final = max(max_y_data + padding_y, min_y_final * 1.01) # Ensure max > min

print(f"\nSetting Y limits (ETH): Min={min_y_final:.4f}, Max={max_y_final:.4f}")
ax.set_ylim(min_y_final, max_y_final)
# --- End Dynamic Y Limits ---


ax.grid(True, linestyle='--', alpha=0.6)

# Consolidate legend
handles, labels = ax.get_legend_handles_labels()
unique_labels = {}
for h, l in zip(handles, labels):
    if l not in unique_labels:
        unique_labels[l] = h
ax.legend(unique_labels.values(), unique_labels.keys())


plt.tight_layout()

# --- Save and Show ---
plt.savefig(OUTPUT_PLOT_PATH)
print(f"\nPlot saved to '{OUTPUT_PLOT_PATH}'")
plt.show()