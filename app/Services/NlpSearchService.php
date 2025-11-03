<?php

namespace App\Services;

/**
 * Stub service for NLP-to-SQL. Intended flow:
 *  - Parse Thai natural language queries into a structured intent
 *  - Map to SQL (or REST filters) for Supabase
 *  - Execute via SupabaseService and return results
 */
class NlpSearchService
{
    public function analyze(string $query): array
    {
        // TODO: Integrate LLM prompt to translate Thai into structured filters/SQL
        return [
            'intent' => 'unknown',
            'filters' => [],
            'original' => $query,
        ];
    }

    public function toSql(array $analysis): string
    {
        // TODO: Map analysis into SQL; ensure parameterization/escaping if executed server-side
        return 'SELECT 1';
    }
}
