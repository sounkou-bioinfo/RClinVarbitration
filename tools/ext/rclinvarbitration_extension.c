/* RClinVarbitration DuckDB extension
 * SPDX-License-Identifier: MIT
 *
 * The native surface is deliberately narrow. libxml2 streams a ClinVar VCV
 * release directly (including gzip files) and emits XML facts as DuckDB rows.
 * SQL, not this parser, defines domain projections and ClinVarbitration rules.
 */
#include "duckdb_extension.h"

#include <libxml/xmlreader.h>

#include <ctype.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

DUCKDB_EXTENSION_EXTERN

#define RCLINVAR_CHUNK_SIZE 1024U
#define RCLINVAR_ERROR_SIZE 512U

typedef struct rclinvar_event {
    uint64_t record_ordinal;
    uint64_t ordinal;
    char *subject_id;
    char *predicate;
    char *object_id;
    char *object_value;
    char *object_kind;
} rclinvar_event_t;

typedef struct rclinvar_stack_entry {
    char *node_id;
    uint64_t next_child_ordinal;
} rclinvar_stack_entry_t;

typedef struct rclinvar_bind_state {
    char *path;
} rclinvar_bind_state_t;

typedef struct rclinvar_scan_state {
    xmlTextReaderPtr reader;
    rclinvar_event_t *events;
    size_t event_count;
    size_t event_capacity;
    size_t event_pos;
    rclinvar_stack_entry_t *stack;
    size_t stack_count;
    size_t stack_capacity;
    uint64_t record_ordinal;
    uint64_t node_ordinal;
    uint64_t statement_ordinal;
    int active_record;
    int finished;
    char error[RCLINVAR_ERROR_SIZE];
} rclinvar_scan_state_t;

static char *rclinvar_strdup(const char *text) {
    size_t n;
    char *out;
    if (!text) return NULL;
    n = strlen(text);
    out = (char *)malloc(n + 1U);
    if (!out) return NULL;
    memcpy(out, text, n + 1U);
    return out;
}

static char *rclinvar_format(const char *format, uint64_t first, uint64_t second) {
    int n;
    char *out;
    n = snprintf(NULL, 0, format, (unsigned long long)first, (unsigned long long)second);
    if (n < 0) return NULL;
    out = (char *)malloc((size_t)n + 1U);
    if (!out) return NULL;
    snprintf(out, (size_t)n + 1U, format, (unsigned long long)first, (unsigned long long)second);
    return out;
}

static char *rclinvar_prefixed(const char *prefix, const char *name) {
    size_t prefix_n;
    size_t name_n;
    char *out;
    if (!prefix || !name) return NULL;
    prefix_n = strlen(prefix);
    name_n = strlen(name);
    out = (char *)malloc(prefix_n + name_n + 1U);
    if (!out) return NULL;
    memcpy(out, prefix, prefix_n);
    memcpy(out + prefix_n, name, name_n + 1U);
    return out;
}

static void rclinvar_set_error(rclinvar_scan_state_t *state, const char *message) {
    if (!state || state->error[0]) return;
    snprintf(state->error, sizeof(state->error), "%s", message ? message : "ClinVar XML parser failed");
}

static void rclinvar_event_clear(rclinvar_event_t *event) {
    if (!event) return;
    free(event->subject_id);
    free(event->predicate);
    free(event->object_id);
    free(event->object_value);
    free(event->object_kind);
    memset(event, 0, sizeof(*event));
}

static void rclinvar_events_reset(rclinvar_scan_state_t *state) {
    size_t i;
    if (!state) return;
    for (i = state->event_pos; i < state->event_count; i++) rclinvar_event_clear(&state->events[i]);
    state->event_count = 0;
    state->event_pos = 0;
}

static int rclinvar_events_reserve(rclinvar_scan_state_t *state, size_t required) {
    size_t capacity;
    rclinvar_event_t *events;
    if (required <= state->event_capacity) return 1;
    capacity = state->event_capacity ? state->event_capacity : 16U;
    while (capacity < required) {
        if (capacity > SIZE_MAX / 2U) {
            rclinvar_set_error(state, "ClinVar XML event queue is too large");
            return 0;
        }
        capacity *= 2U;
    }
    events = (rclinvar_event_t *)realloc(state->events, capacity * sizeof(*events));
    if (!events) {
        rclinvar_set_error(state, "out of memory allocating ClinVar XML event queue");
        return 0;
    }
    memset(events + state->event_capacity, 0, (capacity - state->event_capacity) * sizeof(*events));
    state->events = events;
    state->event_capacity = capacity;
    return 1;
}

static int rclinvar_emit(rclinvar_scan_state_t *state, const char *subject_id, const char *predicate,
                         const char *object_id, const char *object_value, const char *object_kind) {
    rclinvar_event_t *event;
    if (!rclinvar_events_reserve(state, state->event_count + 1U)) return 0;
    event = &state->events[state->event_count];
    event->record_ordinal = state->record_ordinal;
    event->ordinal = ++state->statement_ordinal;
    event->subject_id = rclinvar_strdup(subject_id);
    event->predicate = rclinvar_strdup(predicate);
    event->object_id = object_id ? rclinvar_strdup(object_id) : NULL;
    event->object_value = object_value ? rclinvar_strdup(object_value) : NULL;
    event->object_kind = rclinvar_strdup(object_kind);
    if (!event->subject_id || !event->predicate || !event->object_kind ||
        (object_id && !event->object_id) || (object_value && !event->object_value)) {
        rclinvar_event_clear(event);
        rclinvar_set_error(state, "out of memory copying ClinVar XML statement");
        return 0;
    }
    state->event_count++;
    return 1;
}

static int rclinvar_stack_reserve(rclinvar_scan_state_t *state, size_t required) {
    size_t capacity;
    rclinvar_stack_entry_t *stack;
    if (required <= state->stack_capacity) return 1;
    capacity = state->stack_capacity ? state->stack_capacity : 32U;
    while (capacity < required) {
        if (capacity > SIZE_MAX / 2U) {
            rclinvar_set_error(state, "ClinVar XML nesting is too deep");
            return 0;
        }
        capacity *= 2U;
    }
    stack = (rclinvar_stack_entry_t *)realloc(state->stack, capacity * sizeof(*stack));
    if (!stack) {
        rclinvar_set_error(state, "out of memory allocating ClinVar XML stack");
        return 0;
    }
    memset(stack + state->stack_capacity, 0, (capacity - state->stack_capacity) * sizeof(*stack));
    state->stack = stack;
    state->stack_capacity = capacity;
    return 1;
}

static int rclinvar_stack_push(rclinvar_scan_state_t *state, char *node_id) {
    rclinvar_stack_entry_t *entry;
    if (!rclinvar_stack_reserve(state, state->stack_count + 1U)) return 0;
    entry = &state->stack[state->stack_count++];
    entry->node_id = node_id;
    entry->next_child_ordinal = 0;
    return 1;
}

static void rclinvar_stack_pop(rclinvar_scan_state_t *state) {
    rclinvar_stack_entry_t *entry;
    if (!state || !state->stack_count) return;
    entry = &state->stack[--state->stack_count];
    free(entry->node_id);
    entry->node_id = NULL;
    entry->next_child_ordinal = 0;
}

static int rclinvar_is_whitespace(const char *text) {
    const unsigned char *cursor = (const unsigned char *)text;
    if (!text) return 1;
    while (*cursor) {
        if (!isspace(*cursor)) return 0;
        cursor++;
    }
    return 1;
}

static int rclinvar_start_element(rclinvar_scan_state_t *state, xmlTextReaderPtr reader, const char *local_name) {
    char *node_id = NULL;
    char *element_kind = NULL;
    const char *parent_id = NULL;
    int empty;
    int attribute_status;
    uint64_t child_ordinal = 0;

    node_id = rclinvar_format("clinvar:xml/%llu/%llu", state->record_ordinal, ++state->node_ordinal);
    element_kind = rclinvar_prefixed("xml:element/", local_name);
    if (!node_id || !element_kind) {
        free(node_id);
        free(element_kind);
        rclinvar_set_error(state, "out of memory naming ClinVar XML element");
        return 0;
    }
    if (state->stack_count) {
        parent_id = state->stack[state->stack_count - 1U].node_id;
        child_ordinal = ++state->stack[state->stack_count - 1U].next_child_ordinal;
    }
    if (parent_id && !rclinvar_emit(state, parent_id, "xml:child", node_id, NULL, "node")) goto fail;
    if (!rclinvar_emit(state, node_id, "rdf:type", element_kind, NULL, "node")) goto fail;
    free(element_kind);
    element_kind = NULL;
    if (parent_id) {
        char order[32];
        snprintf(order, sizeof(order), "%llu", (unsigned long long)child_ordinal);
        if (!rclinvar_emit(state, node_id, "xml:child_ordinal", NULL, order, "literal")) goto fail;
    }

    attribute_status = xmlTextReaderMoveToFirstAttribute(reader);
    while (attribute_status == 1) {
        const xmlChar *attribute_name = xmlTextReaderConstLocalName(reader);
        const xmlChar *attribute_value = xmlTextReaderConstValue(reader);
        char *predicate = rclinvar_prefixed("xml:attribute/", (const char *)attribute_name);
        if (!predicate || !rclinvar_emit(state, node_id, predicate, NULL,
                                         attribute_value ? (const char *)attribute_value : "", "literal")) {
            free(predicate);
            goto fail;
        }
        free(predicate);
        attribute_status = xmlTextReaderMoveToNextAttribute(reader);
    }
    if (attribute_status < 0) {
        rclinvar_set_error(state, "failed reading ClinVar XML attributes");
        goto fail;
    }
    xmlTextReaderMoveToElement(reader);
    empty = xmlTextReaderIsEmptyElement(reader);
    if (!rclinvar_stack_push(state, node_id)) goto fail;
    node_id = NULL;
    if (empty) rclinvar_stack_pop(state);
    return 1;

fail:
    free(node_id);
    free(element_kind);
    return 0;
}

static int rclinvar_emit_text(rclinvar_scan_state_t *state, xmlTextReaderPtr reader, const char *predicate) {
    const xmlChar *value;
    const char *subject_id;
    if (!state->stack_count) return 1;
    value = xmlTextReaderConstValue(reader);
    if (!value || rclinvar_is_whitespace((const char *)value)) return 1;
    subject_id = state->stack[state->stack_count - 1U].node_id;
    return rclinvar_emit(state, subject_id, predicate, NULL, (const char *)value, "literal");
}

/* Reads until at least one statement is queued, EOF, or an error. */
static int rclinvar_scan_next(rclinvar_scan_state_t *state) {
    int rc;
    while (!state->finished && state->event_pos == state->event_count) {
        int node_type;
        const xmlChar *local;
        rclinvar_events_reset(state);
        rc = xmlTextReaderRead(state->reader);
        if (rc == 0) {
            state->finished = 1;
            return 0;
        }
        if (rc < 0) {
            const xmlError *error = xmlGetLastError();
            snprintf(state->error, sizeof(state->error), "ClinVar XML parse error%s%s",
                     error && error->message ? ": " : "", error && error->message ? error->message : "");
            return -1;
        }
        node_type = xmlTextReaderNodeType(state->reader);
        local = xmlTextReaderConstLocalName(state->reader);
        if (node_type == XML_READER_TYPE_ELEMENT) {
            if (!state->active_record) {
                if (local && xmlStrEqual(local, BAD_CAST "VariationArchive")) {
                    state->active_record = 1;
                    state->record_ordinal++;
                    state->node_ordinal = 0;
                    state->statement_ordinal = 0;
                    if (!rclinvar_start_element(state, state->reader, (const char *)local)) return -1;
                }
            } else if (!rclinvar_start_element(state, state->reader, (const char *)local)) {
                return -1;
            }
        } else if (state->active_record && node_type == XML_READER_TYPE_END_ELEMENT) {
            if (state->stack_count) rclinvar_stack_pop(state);
            if (local && xmlStrEqual(local, BAD_CAST "VariationArchive")) state->active_record = 0;
        } else if (state->active_record && node_type == XML_READER_TYPE_TEXT) {
            if (!rclinvar_emit_text(state, state->reader, "xml:text")) return -1;
        } else if (state->active_record && node_type == XML_READER_TYPE_CDATA) {
            if (!rclinvar_emit_text(state, state->reader, "xml:cdata")) return -1;
        } else if (state->active_record && node_type == XML_READER_TYPE_COMMENT) {
            if (!rclinvar_emit_text(state, state->reader, "xml:comment")) return -1;
        }
    }
    return state->event_pos < state->event_count ? 1 : 0;
}

static void rclinvar_bind_destroy(void *pointer) {
    rclinvar_bind_state_t *state = (rclinvar_bind_state_t *)pointer;
    if (!state) return;
    free(state->path);
    free(state);
}

static void rclinvar_scan_destroy(void *pointer) {
    size_t i;
    rclinvar_scan_state_t *state = (rclinvar_scan_state_t *)pointer;
    if (!state) return;
    if (state->reader) xmlFreeTextReader(state->reader);
    for (i = 0; i < state->event_count; i++) rclinvar_event_clear(&state->events[i]);
    free(state->events);
    for (i = 0; i < state->stack_count; i++) free(state->stack[i].node_id);
    free(state->stack);
    free(state);
}

static void rclinvar_add_column(duckdb_bind_info info, const char *name, duckdb_type type_id) {
    duckdb_logical_type type = duckdb_create_logical_type(type_id);
    duckdb_bind_add_result_column(info, name, type);
    duckdb_destroy_logical_type(&type);
}

static void rclinvar_xml_bind(duckdb_bind_info info) {
    duckdb_value value = NULL;
    char *path = NULL;
    rclinvar_bind_state_t *state = NULL;
    if (duckdb_bind_get_parameter_count(info) != 1U) {
        duckdb_bind_set_error(info, "clinvar_xml_statements() requires exactly one XML or XML.GZ path");
        return;
    }
    value = duckdb_bind_get_parameter(info, 0);
    path = value ? duckdb_get_varchar(value) : NULL;
    if (value) duckdb_destroy_value(&value);
    if (!path || !path[0]) {
        if (path) duckdb_free(path);
        duckdb_bind_set_error(info, "clinvar_xml_statements() path must be a non-empty string");
        return;
    }
    state = (rclinvar_bind_state_t *)calloc(1, sizeof(*state));
    if (!state) {
        duckdb_free(path);
        duckdb_bind_set_error(info, "out of memory binding clinvar_xml_statements()");
        return;
    }
    state->path = rclinvar_strdup(path);
    duckdb_free(path);
    if (!state->path) {
        rclinvar_bind_destroy(state);
        duckdb_bind_set_error(info, "out of memory copying ClinVar XML path");
        return;
    }
    rclinvar_add_column(info, "record_ordinal", DUCKDB_TYPE_UBIGINT);
    rclinvar_add_column(info, "subject_id", DUCKDB_TYPE_VARCHAR);
    rclinvar_add_column(info, "predicate", DUCKDB_TYPE_VARCHAR);
    rclinvar_add_column(info, "object_id", DUCKDB_TYPE_VARCHAR);
    rclinvar_add_column(info, "object_value", DUCKDB_TYPE_VARCHAR);
    rclinvar_add_column(info, "object_kind", DUCKDB_TYPE_VARCHAR);
    rclinvar_add_column(info, "ordinal", DUCKDB_TYPE_UBIGINT);
    duckdb_bind_set_bind_data(info, state, rclinvar_bind_destroy);
}

static void rclinvar_xml_init(duckdb_init_info info) {
    const rclinvar_bind_state_t *bind = (const rclinvar_bind_state_t *)duckdb_init_get_bind_data(info);
    rclinvar_scan_state_t *state;
    if (!bind || !bind->path) {
        duckdb_init_set_error(info, "clinvar_xml_statements() bind state is missing");
        return;
    }
    state = (rclinvar_scan_state_t *)calloc(1, sizeof(*state));
    if (!state) {
        duckdb_init_set_error(info, "out of memory initializing ClinVar XML scan");
        return;
    }
    state->reader = xmlReaderForFile(bind->path, NULL, XML_PARSE_NONET | XML_PARSE_COMPACT);
    if (!state->reader) {
        rclinvar_scan_destroy(state);
        duckdb_init_set_error(info, "failed to open or parse ClinVar XML/XML.GZ input");
        return;
    }
    duckdb_init_set_max_threads(info, 1);
    duckdb_init_set_init_data(info, state, rclinvar_scan_destroy);
}

static void rclinvar_set_null(duckdb_vector vector, idx_t row) {
    uint64_t *validity;
    duckdb_vector_ensure_validity_writable(vector);
    validity = duckdb_vector_get_validity(vector);
    duckdb_validity_set_row_invalid(validity, row);
}

static void rclinvar_assign_event(duckdb_data_chunk output, idx_t row, rclinvar_event_t *event) {
    uint64_t *record = (uint64_t *)duckdb_vector_get_data(duckdb_data_chunk_get_vector(output, 0));
    duckdb_vector subject = duckdb_data_chunk_get_vector(output, 1);
    duckdb_vector predicate = duckdb_data_chunk_get_vector(output, 2);
    duckdb_vector object_id = duckdb_data_chunk_get_vector(output, 3);
    duckdb_vector object_value = duckdb_data_chunk_get_vector(output, 4);
    duckdb_vector object_kind = duckdb_data_chunk_get_vector(output, 5);
    uint64_t *ordinal = (uint64_t *)duckdb_vector_get_data(duckdb_data_chunk_get_vector(output, 6));
    record[row] = event->record_ordinal;
    ordinal[row] = event->ordinal;
    duckdb_vector_assign_string_element(subject, row, event->subject_id);
    duckdb_vector_assign_string_element(predicate, row, event->predicate);
    duckdb_vector_assign_string_element(object_kind, row, event->object_kind);
    if (event->object_id) duckdb_vector_assign_string_element(object_id, row, event->object_id);
    else rclinvar_set_null(object_id, row);
    if (event->object_value) duckdb_vector_assign_string_element(object_value, row, event->object_value);
    else rclinvar_set_null(object_value, row);
}

static void rclinvar_xml_function(duckdb_function_info info, duckdb_data_chunk output) {
    rclinvar_scan_state_t *state = (rclinvar_scan_state_t *)duckdb_function_get_init_data(info);
    idx_t count = 0;
    if (!state) {
        duckdb_function_set_error(info, "clinvar_xml_statements() scan state is missing");
        duckdb_data_chunk_set_size(output, 0);
        return;
    }
    while (count < RCLINVAR_CHUNK_SIZE) {
        rclinvar_event_t event;
        int status;
        if (state->event_pos >= state->event_count) {
            status = rclinvar_scan_next(state);
            if (status < 0) {
                duckdb_function_set_error(info, state->error[0] ? state->error : "ClinVar XML scan failed");
                duckdb_data_chunk_set_size(output, 0);
                return;
            }
            if (status == 0) break;
        }
        event = state->events[state->event_pos];
        memset(&state->events[state->event_pos], 0, sizeof(event));
        state->event_pos++;
        rclinvar_assign_event(output, count, &event);
        rclinvar_event_clear(&event);
        count++;
    }
    duckdb_data_chunk_set_size(output, count);
}

static bool rclinvar_register_xml_statements(duckdb_connection connection) {
    duckdb_table_function function = duckdb_create_table_function();
    duckdb_logical_type parameter_type;
    duckdb_state state;
    if (!function) return false;
    parameter_type = duckdb_create_logical_type(DUCKDB_TYPE_VARCHAR);
    if (!parameter_type) {
        duckdb_destroy_table_function(&function);
        return false;
    }
    duckdb_table_function_set_name(function, "clinvar_xml_statements");
    duckdb_table_function_add_parameter(function, parameter_type);
    duckdb_destroy_logical_type(&parameter_type);
    duckdb_table_function_set_bind(function, rclinvar_xml_bind);
    duckdb_table_function_set_init(function, rclinvar_xml_init);
    duckdb_table_function_set_function(function, rclinvar_xml_function);
    state = duckdb_register_table_function(connection, function);
    duckdb_destroy_table_function(&function);
    return state == DuckDBSuccess;
}

DUCKDB_EXTENSION_ENTRYPOINT(duckdb_connection connection,
                            duckdb_extension_info info,
                            struct duckdb_extension_access *access) {
    xmlInitParser();
    if (!rclinvar_register_xml_statements(connection)) {
        access->set_error(info, "failed to register clinvar_xml_statements()");
        return false;
    }
    return true;
}
