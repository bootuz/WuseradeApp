"""Picking, ranking and scheduling rules for Wuserade's daily discovery.

Pure Python: nothing here talks to Firebase except `catalog.load_catalog`, which reads
through the Firestore client it is given. The Cloud Functions and the admin tool's `rebuild`
share this package.
"""
