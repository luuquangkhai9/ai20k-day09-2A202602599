SELECT drive_id, trip_id, frames, frames_kept,
       ROUND(100.0 * (frames - frames_kept) / NULLIF(frames, 0), 2) AS dropped_pct
FROM marts.mart_trip_summary
ORDER BY dropped_pct DESC NULLS LAST, trip_id;
