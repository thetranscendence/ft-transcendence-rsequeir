/**
 * Type unifié pour gérer toutes les formes d'erreurs possibles dans le Global Handler.
 * Il couvre :
 * - FastifyError (code, statusCode, message, stack)
 * - Error natif (message, name, stack)
 * - Objets d'erreurs personnalisés ({ statusCode, message, payload })
 */
export interface ServiceError {
  statusCode?: number;
  code?: string;
  name?: string;
  message?: string;
  stack?: string;
  payload?: unknown; // Pour nos données contextuelles custom
  [key: string]: unknown; // Index signature pour tolérer d'autres propriétés
}